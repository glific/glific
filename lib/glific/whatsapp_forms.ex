defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo
  alias Glific.WhatsappForms.WhatsappForm
  alias Glific.ThirdParty.Meta.ApiClientMeta
  require Logger

  @doc """
  Fetch a WhatsApp form by ID.
  """
  @spec get_whatsapp_form!(integer()) :: WhatsappForm.t()
  def get_whatsapp_form!(id), do: Repo.get!(WhatsappForm, id)

  @doc """
  Publish a WhatsApp form to Meta Graph API.
  Updates the form's status to :published on success.
  """
  @spec publish_whatsapp_form(WhatsappForm.t()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def publish_whatsapp_form(%WhatsappForm{} = form) do
    case ApiClientMeta.publish_wa_form(form.meta_flow_id) do
      {:ok, _response} ->
        form
        |> Ecto.Changeset.change(status: :published)
        |> Repo.update()

      {:error, reason} ->
        Logger.error("Failed to publish WhatsApp form #{form.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec deactivate_wa_form(non_neg_integer(), non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def deactivate_wa_form(form_id, org_id) do
    case Repo.get_by(WhatsappForm, id: form_id, organization_id: org_id) do
      nil ->
        {:error, "WhatsApp form not found"}

      form ->
        form
        |> WhatsappForm.changeset(%{status: :inactive})
        |> Repo.update()
    end
  end
end
