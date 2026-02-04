defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Glific.{
    Enums.WhatsappFormCategory,
    Notifications,
    Partners,
    Providers.Gupshup.PartnerAPI,
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    Sheets,
    Sheets.GoogleSheets,
    Sheets.Sheet,
    Users.User,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormRevision,
    WhatsappForms.WhatsappFormWorker,
    WhatsappFormsRevisions
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
  Creates a WhatsApp form with an initial revision
  """
  @spec create_whatsapp_form(map(), User.t()) :: {:ok, map()} | {:error, any()}
  def create_whatsapp_form(attrs, user) do
    attrs = Map.put(attrs, :operation, :create)

    with {:ok, response} <- ApiClient.create_whatsapp_form(attrs),
         {:ok, updated_attrs} <- maybe_create_google_sheet(attrs),
         {:ok, db_attrs} <- prepare_attrs(updated_attrs, response),
         {:ok, whatsapp_form} <- do_create_whatsapp_form(db_attrs),
         {:ok, revision} <- create_whatsapp_form_revision(whatsapp_form, user),
         {:ok, _} <- update_revision_id(whatsapp_form.id, revision.id),
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
    attrs =
      attrs
      |> Map.put(:operation, :update)
      |> Map.put(:sheet_id, form.sheet_id)

    with {:ok, response} <- ApiClient.update_whatsapp_form(form.meta_flow_id, attrs),
         {:ok, updated_attrs} <- maybe_create_google_sheet(attrs),
         {:ok, db_attrs} <- prepare_attrs(updated_attrs, response),
         {:ok, whatsapp_form} <- do_update_whatsapp_form(form, db_attrs) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    end
  end

  @doc """
  Syncs a WhatsApp form from Gupshup
  """
  @spec sync_whatsapp_form(non_neg_integer()) ::
          {:ok, String.t()} | {:error, any()}
  def sync_whatsapp_form(organization_id) do
    with {:ok, forms} <- ApiClient.list_whatsapp_forms(organization_id),
         {:ok, _} <- sync_all_forms_for_org(forms, organization_id) do
      {:ok, %{message: "Syncing of WhatsApp forms has started in the background."}}
    end
  end

  @doc """
  Handles syncing of a all WhatsApp form.
  """
  @spec sync_all_forms_for_org(list(map()), non_neg_integer()) :: {:ok, any()} | {:error, any()}
  def sync_all_forms_for_org(forms, org_id) do
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

    Notifications.create_notification(%{
      category: "WhatsApp Forms",
      message: "Syncing of whatsapp form templates has started in the background.",
      severity: Notifications.types().info,
      organization_id: org_id,
      entity: %{Provider: "Gupshup"}
    })

    WhatsappFormWorker.schedule_next_form_sync(forms, org_id)
  end

  @doc """
    Publishes a WhatsApp form through the configured provider (e.g., Gupshup).
  """
  @spec publish_whatsapp_form(non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}

  def publish_whatsapp_form(id) do
    with {:ok, form} <- get_whatsapp_form_by_id(id),
         {:ok, _} <-
           ApiClient.update_whatsapp_form_json(form),
         {:ok, _response} <-
           ApiClient.publish_whatsapp_form(form.meta_flow_id, form.organization_id),
         {:ok, updated_form} <- update_form_status(form, :published),
         {:ok, _} <- append_headers_to_sheet(form) do
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
    case Repo.fetch_by(WhatsappForm, %{id: id}) do
      {:ok, whatsapp_form} ->
        {:ok, Repo.preload(whatsapp_form, [:sheet, :revision])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the list of whatsapp forms.
  """
  @spec list_whatsapp_forms(map()) :: [WhatsappForm.t()]
  def list_whatsapp_forms(args),
    do: Repo.list_filter(args, WhatsappForm, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Updates the WhatsApp form JSON with the definition from the given revision
  """
  @spec update_revision_id(non_neg_integer(), non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, any()}
  def update_revision_id(whatsapp_form_id, revision_id) do
    with {:ok, form} <- get_whatsapp_form_by_id(whatsapp_form_id) do
      form
      |> WhatsappForm.changeset(%{revision_id: revision_id})
      |> Repo.update()
    end
  end

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

  @spec prepare_attrs(map(), map()) :: {:ok, map()}
  defp prepare_attrs(%{operation: :create} = validated_attrs, api_response) do
    db_attrs = %{
      name: validated_attrs.name,
      organization_id: validated_attrs.organization_id,
      meta_flow_id: api_response.id,
      status: "draft",
      description: validated_attrs.description,
      categories: validated_attrs.categories,
      sheet_id: validated_attrs.sheet_id
    }

    {:ok, db_attrs}
  end

  defp prepare_attrs(%{operation: :update} = validated_attrs, _api_response) do
    db_attrs = %{
      name: validated_attrs.name,
      description: Map.get(validated_attrs, :description),
      categories: validated_attrs.categories,
      organization_id: validated_attrs.organization_id,
      sheet_id: validated_attrs.sheet_id
    }

    {:ok, db_attrs}
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
      description: Map.get(form, "description", ""),
      meta_flow_id: form["id"],
      definition: form_json,
      organization_id: organization_id
    }

    organization = Partners.organization(organization_id)
    root_user = organization.root_user

    case Repo.fetch_by(WhatsappForm, %{meta_flow_id: form["id"], organization_id: organization_id}) do
      {:ok, existing_form} ->
        existing_form_revision = Repo.preload(existing_form, :revision)

        case form_changed?(existing_form_revision, attrs) do
          false ->
            {:ok, existing_form}

          true ->
            revision_attrs = %{
              whatsapp_form_id: existing_form.id,
              definition: form_json
            }

            attrs_with_description =
              Map.put(attrs, :description, existing_form.description)

            with {:ok, _revision} <-
                   WhatsappFormsRevisions.save_revision(revision_attrs, root_user) do
              do_update_whatsapp_form(existing_form, attrs_with_description)
            end
        end

      {:error, _} ->
        with {:ok, whatsapp_form} <- do_create_whatsapp_form(attrs),
             {:ok, revision} <- create_whatsapp_form_revision(whatsapp_form, root_user) do
          update_revision_id(whatsapp_form.id, revision.id)
        end
    end
  end

  @doc """
  Creates a WhatsApp form in the database.
  """
  @spec do_create_whatsapp_form(map()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  def do_create_whatsapp_form(attrs) do
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

  @spec maybe_set_subscription(non_neg_integer()) :: :ok | {:error, any()}
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

  @spec maybe_create_google_sheet(map()) ::
          {:ok, map()} | {:error, any()}
  defp maybe_create_google_sheet(attrs) do
    url = Map.get(attrs, :google_sheet_url)

    if url in [nil, ""] do
      {:ok, Map.put(attrs, :sheet_id, nil)}
    else
      handle_google_sheet(attrs, url)
    end
  end

  @spec handle_google_sheet(map(), String.t()) :: {:ok, map()} | {:error, any()}
  defp handle_google_sheet(%{operation: :update, sheet_id: sheet_id} = attrs, url)
       when not is_nil(sheet_id) do
    update_existing_sheet(attrs, url, sheet_id)
  end

  defp handle_google_sheet(%{operation: operation} = attrs, url)
       when operation in [:create, :update] do
    create_new_sheet(attrs, url)
  end

  @spec create_new_sheet(map(), String.t()) ::
          {:ok, map()} | {:error, any()}
  defp create_new_sheet(attrs, url) do
    case Sheets.create_sheet(%{
           label: "WhatsApp Form - #{attrs.name}",
           organization_id: attrs.organization_id,
           url: url,
           type: "WRITE"
         }) do
      {:ok, sheet} ->
        {:ok, Map.put(attrs, :sheet_id, sheet.id)}

      {:error, reason} ->
        Logger.error("Failed to create Google Sheet for WhatsApp form: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec update_existing_sheet(map(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  defp update_existing_sheet(attrs, url, sheet_id) do
    case Repo.fetch_by(Sheet, %{id: sheet_id}) do
      {:ok, sheet} ->
        case Sheets.update_sheet(sheet, %{
               url: url,
               label: "WhatsApp Form - #{attrs.name}",
               type: "WRITE",
               organization_id: attrs.organization_id
             }) do
          {:ok, updated_sheet} ->
            {:ok, Map.put(attrs, :sheet_id, updated_sheet.id)}

          {:error, reason} ->
            Logger.error("Failed to update Google Sheet for WhatsApp form: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "Failed to fetch existing Google Sheet for WhatsApp form: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
    Appends headers to the Google Sheet associated with the WhatsApp form.
  """
  @spec append_headers_to_sheet(WhatsappForm.t()) :: {:ok, any()} | {:error, any()}
  def append_headers_to_sheet(%{sheet_id: nil}), do: {:ok, nil}

  def append_headers_to_sheet(%{
        revision: %{definition: %{"screens" => screens}},
        sheet: %{url: url},
        organization_id: organization_id
      }) do
    with {:ok, complete_payload} <- extract_complete_payload(screens),
         spreadsheet_id <- Sheets.extract_spreadsheet_id(url),
         headers <- build_headers(complete_payload),
         {:ok, _result} <- insert_headers(organization_id, spreadsheet_id, headers) do
      {:ok, headers}
    end
  end

  def append_headers_to_sheet(_), do: {:error, "Invalid form structure"}

  @spec extract_complete_payload(list()) :: {:ok, map()} | {:error, String.t()}
  defp extract_complete_payload(screens) do
    payload =
      screens
      |> Enum.find_value(&find_complete_action/1)

    case payload do
      nil -> {:error, "No complete action payload found"}
      payload -> {:ok, payload}
    end
  end

  @spec find_complete_action(map()) :: map() | nil
  defp find_complete_action(%{"layout" => %{"children" => children}}) do
    children
    |> Enum.flat_map(fn child ->
      get_in(child, ["children"]) || []
    end)
    |> Enum.find_value(&extract_payload_from_child/1)
  end

  defp find_complete_action(_), do: nil

  @spec extract_payload_from_child(map()) :: map() | nil
  defp extract_payload_from_child(%{
         "on-click-action" => %{"name" => "complete", "payload" => payload}
       }),
       do: payload

  defp extract_payload_from_child(_), do: nil

  @spec build_headers(map()) :: list(String.t())
  defp build_headers(complete_payload) do
    default_headers = [
      "timestamp",
      "contact_phone_number",
      "whatsapp_form_id",
      "whatsapp_form_name"
    ]

    form_headers = complete_payload |> Map.keys() |> Enum.map(&to_string/1)

    default_headers ++ form_headers
  end

  @spec insert_headers(non_neg_integer(), String.t(), list(String.t())) ::
          {:ok, any()} | {:error, any()}
  defp insert_headers(organization_id, spreadsheet_id, headers) do
    GoogleSheets.insert_row(organization_id, spreadsheet_id, %{
      range: "A1",
      data: [headers]
    })
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

  @spec normalize_status(any()) :: atom() | String.t()

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.downcase()
    |> String.to_existing_atom()
  end

  @spec form_changed?(map(), map()) :: boolean()
  defp form_changed?(%WhatsappForm{} = existing_form, attrs) do
    comparable_fields = [:name, :definition, :categories, :status]

    Enum.any?(comparable_fields, fn field ->
      Map.get(existing_form, field) != Map.get(attrs, field)
    end)
  end

  @doc """
  Creates a WhatsApp form revision.
  """
  @spec create_whatsapp_form_revision(WhatsappForm.t(), User.t()) ::
          {:ok, WhatsappFormRevision.t()} | {:error, any()}
  def create_whatsapp_form_revision(whatsapp_form, user) do
    WhatsappFormsRevisions.create_revision(%{
      whatsapp_form_id: whatsapp_form.id,
      definition: WhatsappFormsRevisions.default_definition(),
      user_id: user.id,
      organization_id: whatsapp_form.organization_id
    })
  end
end
