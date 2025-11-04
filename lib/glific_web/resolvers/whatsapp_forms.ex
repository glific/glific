defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
  Resolver for publishing a WhatsApp form.
  """
  alias Glific.WhatsappForms
  alias Glific.WhatsappForms.WhatsappForm

  @doc """
    Publishes a WhatsApp form using its Meta Flow ID.

  """
  @spec publish_whatsapp_form(any(), %{id: String.t()}, Absinthe.Resolution.t()) ::
          {:ok, %{status: String.t(), body: WhatsappForm.t()}} | {:error, String.t()}
  def publish_whatsapp_form(_parent, %{id: id}, _resolution) do
    with {:ok, %WhatsappForm{}} = {:ok, form} <-
           WhatsappForms.get_whatsapp_form_by_id(id),
         {:ok, updated_form} <- WhatsappForms.publish_whatsapp_form(form) do
      {:ok, %{status: "success", body: updated_form}}
    else
      {:error, reason} ->
        {:error, "Failed to publish WhatsApp Form: #{reason}"}
    end
  end

  @doc """
  Deactivates an existing WhatsApp form.
  """
  @spec deactivate_wa_form(any(), %{form_id: String.t()}, Absinthe.Resolution.t()) ::
          {:ok, %{status: String.t(), body: WhatsappForm.t()}} | {:error, String.t()}
  def deactivate_wa_form(_parent, %{form_id: form_id}, _resolution) do
    case WhatsappForms.deactivate_wa_form(form_id) do
      {:ok, updated_form} ->
        {:ok, %{status: "success", body: updated_form}}

      {:error, msg} ->
        {:error, msg}
    end
  end
end
