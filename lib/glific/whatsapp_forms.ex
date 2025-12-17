defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Glific.{
    Enums.WhatsappFormCategory,
    Notifications,
    Providers.Gupshup.PartnerAPI,
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormWorker
  }

  require Logger

  @doc """
  Lists all available WhatsApp form categories
  """
  @spec list_whatsapp_form_categories() :: {:ok, list(String.t())}
  def list_whatsapp_form_categories do
    categories =
      WhatsappFormCategory.__enum_map__()
      |> Enum.map(&Atom.to_string/1)

    {:ok, categories}
  end

  @doc """
  Creates a WhatsApp form
  """
  @spec create_whatsapp_form(map()) :: {:ok, map()} | {:error, any()}
  def create_whatsapp_form(attrs) do
    with {:ok, response} <- ApiClient.create_whatsapp_form(attrs),
         {:ok, db_attrs} <- prepare_attrs(attrs, response, :create),
         {:ok, whatsapp_form} <- do_create_whatsapp_form(db_attrs),
         :ok <- maybe_set_subscription(attrs.organization_id) do
      # Track metric for WhatsApp form creation
      Glific.Metrics.increment("WhatsApp Form Created", attrs.organization_id)
      {:ok, %{whatsapp_form: whatsapp_form}}
    end
  end

  @doc """
  Updates a WhatsApp form
  """
  @spec update_whatsapp_form(WhatsappForm.t(), map()) :: {:ok, map()} | {:error, any()}
  def update_whatsapp_form(%WhatsappForm{} = form, attrs) do
    with {:ok, response} <- ApiClient.update_whatsapp_form(form.meta_flow_id, attrs),
         {:ok, db_attrs} <- prepare_attrs(attrs, response, :update),
         {:ok, whatsapp_form} <- do_update_whatsapp_form(form, db_attrs) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    end
  end

  @doc """
  Syncs a WhatsApp form from Gupshup
  """
  @spec sync_whatsapp_form(non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  def sync_whatsapp_form(organization_id) do
    case ApiClient.list_whatsapp_forms(organization_id) do
      {:ok, forms} ->
        {handle_single_form(forms, organization_id),
         %{message: "Syncing of the form has been started in the background"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Handles syncing of a single WhatsApp form.
  """
  @spec handle_single_form(list(map()), non_neg_integer()) :: :ok
  def handle_single_form(forms, org_id) do
    meta_flow_ids =
      forms
      |> Enum.map(fn form -> form.id end)

    published_ids =
      WhatsappForm
      |> where([w], w.meta_flow_id in ^meta_flow_ids and w.status == :published)
      |> select([w], w.meta_flow_id)
      |> Repo.all()
      |> MapSet.new()

    forms =
      Enum.reject(forms, fn form ->
        MapSet.member?(published_ids, form.id)
      end)

    WhatsappFormWorker.schedule_next_form_sync(forms, org_id)

    Notifications.create_notification(%{
      category: "WhatsApp Forms",
      message: "Syncing of whatsapp form templates has started in the background.",
      severity: Notifications.types().info,
      organization_id: org_id,
      entity: %{Provider: "Gupshup"}
    })

    :ok
  end

  @doc """
    Publishes a WhatsApp form through the configured provider (e.g., Gupshup).
  """
  @spec publish_whatsapp_form(non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}

  def publish_whatsapp_form(id) do
    with {:ok, form} <- get_whatsapp_form_by_id(id),
         {:ok, _response} <-
           ApiClient.publish_whatsapp_form(form.meta_flow_id, form.organization_id),
         {:ok, updated_form} <- update_form_status(form, :published) do
      {:ok, %{whatsapp_form: updated_form}}
    end
  end

  @doc """
  Deactivates a WhatsApp form by its Meta Flow ID.
  """
  @spec deactivate_whatsapp_form(non_neg_integer()) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}} | {:error, String.t()}
  def deactivate_whatsapp_form(id) do
    with {:ok, form} <- get_whatsapp_form_by_id(id),
         {:ok, updated_form} <- update_form_status(form, :inactive) do
      {:ok, %{whatsapp_form: updated_form}}
    end
  end

  @doc """
  Activate a WhatsApp form by its Meta Flow ID.

  Publishing a form makes the flow live and ready for use.
  If a form has been previously deactivated (which temporarily prevents NGOs from using it),
  this function activates it again and makes it available for use.
  """
  @spec activate_whatsapp_form(non_neg_integer()) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}} | {:error, String.t()}
  def activate_whatsapp_form(id) do
    with {:ok, form} <- get_whatsapp_form_by_id(id),
         {:ok, updated_form} <- update_form_status(form, :published) do
      {:ok, %{whatsapp_form: updated_form}}
    end
  end

  @doc """
  Fetches a WhatsApp form by its ID
  """
  @spec get_whatsapp_form_by_id(non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, any()}
  def get_whatsapp_form_by_id(id) do
    Repo.fetch_by(WhatsappForm, %{id: id})
  end

  @doc """
  Returns the list of whatsapp forms.
  """
  @spec list_whatsapp_forms(map()) :: [WhatsappForm.t()]
  def list_whatsapp_forms(args),
    do: Repo.list_filter(args, WhatsappForm, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of whatsapp forms
  """
  @spec count_whatsapp_forms(map()) :: integer
  def count_whatsapp_forms(args),
    do: Repo.count_filter(args, WhatsappForm, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from(q in query, where: q.status == ^status)

      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:meta_flow_id, meta_flow_id}, query ->
        from(q in query, where: q.meta_flow_id == ^meta_flow_id)
    end)
  end

  @spec update_form_status(WhatsappForm.t(), atom()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  defp update_form_status(%WhatsappForm{} = form, new_status) do
    form
    |> Ecto.Changeset.change(status: new_status)
    |> Repo.update()
  end

  @doc """
  Saves or updates a single form from WBM.
  """
  @spec sync_single_form(map(), map(), non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  def sync_single_form(form, form_json, organization_id) do
    attrs = %{
      name: form["name"],
      status: normalize_status(form["status"]),
      categories: normalize_categories(form["categories"]),
      definition: form_json,
      description: Map.get(form, "description", ""),
      meta_flow_id: form["id"],
      organization_id: organization_id
    }

    case Repo.fetch_by(WhatsappForm, %{meta_flow_id: form["id"], organization_id: organization_id}) do
      {:ok, existing_form} ->
        case form_changed?(existing_form, attrs) do
          false ->
            {:ok, existing_form}

          true ->
            do_update_whatsapp_form(existing_form, attrs)
        end

      {:error, _} ->
        do_create_whatsapp_form(attrs)
    end
  end

  @spec prepare_attrs(map(), map(), :create | :update) ::
          {:ok, map()}
  defp prepare_attrs(validated_attrs, api_response, :create) do
    db_attrs = %{
      name: validated_attrs.name,
      organization_id: validated_attrs.organization_id,
      definition: validated_attrs.form_json,
      meta_flow_id: api_response.id,
      status: "draft",
      description: validated_attrs.description,
      categories: validated_attrs.categories
    }

    {:ok, db_attrs}
  end

  defp prepare_attrs(validated_attrs, _, :update) do
    db_attrs = %{
      name: validated_attrs.name,
      definition: validated_attrs.form_json,
      description: Map.get(validated_attrs, :description),
      categories: validated_attrs.categories,
      organization_id: validated_attrs.organization_id
    }

    {:ok, db_attrs}
  end

  @spec do_create_whatsapp_form(map()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  defp do_create_whatsapp_form(attrs) do
    %WhatsappForm{}
    |> WhatsappForm.changeset(attrs)
    |> Repo.insert()
  end

  @spec do_update_whatsapp_form(WhatsappForm.t(), map()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  defp do_update_whatsapp_form(form, attrs) do
    with {:ok, whatsapp_form} <- get_whatsapp_form_by_id(form.id) do
      whatsapp_form
      |> WhatsappForm.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a WhatsApp form belonging to a specific organization by its ID.
  """
  @spec delete_whatsapp_form(non_neg_integer()) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}} | {:error, String.t()}
  def delete_whatsapp_form(id) do
    with {:ok, whatsapp_form} <- Repo.fetch_by(WhatsappForm, %{id: id}),
         {:ok, delete_form} <- Repo.delete(whatsapp_form) do
      {:ok, %{whatsapp_form: delete_form}}
    end
  end

  @spec maybe_set_subscription(non_neg_integer()) :: :ok
  defp maybe_set_subscription(organization_id) do
    # Check if this is the first form for the organization
    with 1 <- count_whatsapp_forms(%{organization_id: organization_id}),
         {:ok, _response} <-
           PartnerAPI.set_subscription(
             organization_id,
             nil,
             ["FLOW_MESSAGE"],
             3,
             "whatsapp_forms_webhook"
           ) do
      :ok
    else
      {:error, %Tesla.Env{body: body, status: 400}} ->
        if String.contains?(body, "Duplicate component tag") do
          :ok
        else
          Logger.error("Failed to set subscription for org #{organization_id}: #{inspect(body)}")
          {:error, body}
        end

      {:error, error} ->
        Logger.error("Failed to set subscription for org #{organization_id}: #{inspect(error)}")
        {:error, error}

      # Any other count (not 1) means it's not the first form
      _count ->
        :ok
    end
  end

  @spec normalize_status(any()) :: atom() | String.t()

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.downcase()
    |> String.to_existing_atom()
  end

  @spec normalize_categories(any()) :: list(atom() | String.t())

  defp normalize_categories(categories) when is_list(categories) do
    Enum.map(categories, fn category ->
      category
      |> to_string()
      |> String.downcase()
      |> String.to_existing_atom()
    end)
  end

  @spec form_changed?(map(), map()) :: boolean()
  defp form_changed?(%WhatsappForm{} = existing_form, attrs) do
    comparable_fields = [:name, :definition, :categories, :status]

    Enum.any?(comparable_fields, fn field ->
      Map.get(existing_form, field) != Map.get(attrs, field)
    end)
  end
end
