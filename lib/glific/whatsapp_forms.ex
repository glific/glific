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
         {:ok, db_attrs} <- prepare_attrs(attrs, response, :create),
         {:ok, whatsapp_form} <- create_whatsapp_form_entry(db_attrs) do
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
         {:ok, whatsapp_form} <- update_whatsapp_form_entry(form, db_attrs) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    end
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
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def deactivate_whatsapp_form(id) do
    with {:ok, form} <- get_whatsapp_form_by_id(id),
         {:ok, updated_form} <- update_form_status(form, :inactive) do
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

  @spec update_form_status(WhatsappForm.t(), atom()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  defp update_form_status(%WhatsappForm{} = form, new_status) do
    form
    |> Ecto.Changeset.change(status: new_status)
    |> Repo.update()
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

  @spec create_whatsapp_form_entry(map()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  defp create_whatsapp_form_entry(attrs) do
    %WhatsappForm{}
    |> WhatsappForm.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_whatsapp_form_entry(WhatsappForm.t(), map()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  defp update_whatsapp_form_entry(form, attrs) do
    {:ok, whatsapp_form} = get_whatsapp_form_by_id(form.id)

    whatsapp_form
    |> WhatsappForm.changeset(attrs)
    |> Repo.update()
  end
end
