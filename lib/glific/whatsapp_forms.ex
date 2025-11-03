defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """

  import Ecto.Query, warn: false
  alias Glific.Providers.Gupshup.WhatsappForms.ApiClient
  alias Glific.Repo
  alias Glific.WhatsappForms.WhatsappForm

  require Logger

  @doc false
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

  @doc false
  @spec deactivate_wa_form(String.t()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def deactivate_wa_form(meta_form_id) do
    case get_whatsapp_form_by_meta_flow_id(meta_form_id) do
      nil ->
        {:error, "WhatsApp form not found"}

      %WhatsappForm{} = form ->
        update_form_status(form, :inactive)
    end
  end

  @doc false
  @spec get_whatsapp_form_by_meta_flow_id(String.t()) :: WhatsappForm.t() | nil
  def get_whatsapp_form_by_meta_flow_id(meta_flow_id) do
    Repo.get_by(WhatsappForm, meta_flow_id: meta_flow_id)
  end

  @spec update_form_status(WhatsappForm.t(), atom()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  defp update_form_status(%WhatsappForm{} = form, new_status) do
    form
    |> Ecto.Changeset.change(status: new_status)
    |> Repo.update()
    |> case do
      {:ok, updated_form} ->
        {:ok, updated_form}

      {:error, changeset} ->
        {:error, "Failed to update form status: #{inspect(changeset.errors)}"}
    end
  end
end
