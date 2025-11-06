defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Enums.WhatsappFormCategory,
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    WhatsappForms.WhatsappForm
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
         {:ok, db_attrs} <- prepare_db_attrs(attrs, response, :create),
         {:ok, whatsapp_form} <- WhatsappForm.create_whatsapp_form(db_attrs) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a WhatsApp form
  """
  @spec update_whatsapp_form(non_neg_integer(), map()) :: {:ok, map()} | {:error, any()}
  def update_whatsapp_form(id, attrs) do
    with {:ok, flow} <- WhatsappForm.get_whatsapp_form_by_id(id),
         {:ok, response} <- ApiClient.update_whatsapp_form(flow.meta_flow_id, attrs),
         {:ok, db_attrs} <- prepare_db_attrs(attrs, response, :update),
         {:ok, whatsapp_form} <- WhatsappForm.update_whatsapp_form(id, db_attrs) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
    Publishes a WhatsApp form through the configured provider (e.g., Gupshup).
  """
  @spec publish_whatsapp_form(WhatsappForm.t()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def publish_whatsapp_form(%WhatsappForm{} = form) do
    case ApiClient.publish_wa_form(form.meta_flow_id, form.organization_id) do
      {:ok, _response} ->
        update_form_status(form, :published)

      {:error, reason} ->
        Logger.error("Failed to publish WhatsApp form #{form.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deactivates a WhatsApp form by its Meta Flow ID.
  """
  @spec deactivate_wa_form(WhatsappForm.t()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def deactivate_wa_form(form) do
    update_form_status(form, :inactive)
  end

  @doc """
  Fetches a WhatsApp form from the database using its whatsapp form ID.
  """
  @spec get_whatsapp_form_by_id(String.t()) ::
          {:ok, WhatsappForm.t()} | {:error, any()}
  def get_whatsapp_form_by_id(form_id) do
    Repo.fetch_by(WhatsappForm, %{id: form_id})
  end

  @spec update_form_status(WhatsappForm.t(), atom()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  defp update_form_status(%WhatsappForm{} = form, new_status) do
    form
    |> Ecto.Changeset.change(status: new_status)
    |> Repo.update()
  end

  @spec prepare_db_attrs(map(), map(), :create | :update) ::
          {:ok, map()}
  defp prepare_db_attrs(validated_attrs, api_response, :create) do
    db_attrs = %{
      name: validated_attrs.name,
      organization_id: validated_attrs.organization_id,
      definition: validated_attrs.form_json,
      meta_flow_id: Map.get(api_response, :id),
      status: "draft",
      description: Map.get(validated_attrs, :description),
      categories: validated_attrs.categories |> Enum.map(&String.downcase/1)
    }

    {:ok, db_attrs}
  end

  defp prepare_db_attrs(validated_attrs, _, :update) do
    db_attrs = %{
      name: validated_attrs.name,
      definition: validated_attrs.form_json,
      description: Map.get(validated_attrs, :description),
      categories: validated_attrs.categories |> Enum.map(&String.downcase/1)
    }

    {:ok, db_attrs}
  end
end
