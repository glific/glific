defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
  Resolver for Meta API related operations.
  """

  alias Glific.ThirdParty.Meta.ApiClientMeta

  @doc """
  Resolver for publishing a WhatsApp form.
  """
  def publish_whatsapp_form(_parent, %{id: id}, _resolution) do
    form = WhatsappForms.get_whatsapp_form!(id)

    case WhatsappForms.publish_whatsapp_form(form) do
      {:ok, updated_form} ->
        {:ok, %{status: :success, form: updated_form}}

      {:error, reason} ->
        {:error, "Failed to publish WhatsApp Form: #{reason}"}
    end
  end

  @doc """
  Deactivate a WhatsApp form.
  """
  def deactivate_wa_form(_parent, %{form_id: form_id}, %{context: %{organization_id: org_id}}) do
    case WhatsappForms.deactivate_wa_form(form_id, org_id) do
      {:ok, form} -> {:ok, %{status: "success", form: form}}
      {:error, msg} -> {:error, msg}
    end
  end
end
