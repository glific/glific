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
    with {:ok, %WhatsappForm{} = form} <-
           WhatsappForms.get_whatsapp_form_by_id(id),
         {:ok, updated_form} <- WhatsappForms.publish_whatsapp_form(form) do
      {:ok, %{status: "success", body: updated_form}}
    else
      {:error, reason} ->
        {:error, "Failed to publish WhatsApp Form: #{reason}"}
    end
  end

  @doc """
  Get the count of whatsapp forms filtered by args
  """
  @spec count_whatsapp_forms(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_whatsapp_forms(_, args, _) do
    {:ok, WhatsappForms.count_whatsapp_forms(args)}
  end

  @doc """
  Get the list of whatsapp forms filtered by args
  """
  @spec list_whatsapp_forms(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def list_whatsapp_forms(_, args, _) do
    {:ok, WhatsappForms.list_whatsapp_forms(args)}
  end

  @doc """
  Deactivates an existing WhatsApp form.
  """
  @spec deactivate_wa_form(any(), %{id: String.t()}, Absinthe.Resolution.t()) ::
          {:ok, %{status: String.t(), body: WhatsappForm.t()}} | {:error, any()}
  def deactivate_wa_form(_parent, %{id: form_id}, _resolution) do
    with {:ok, %WhatsappForm{} = form} <-
           WhatsappForms.get_whatsapp_form_by_id(form_id),
         {:ok, updated_form} <- WhatsappForms.deactivate_wa_form(form) do
      {:ok, %{status: "success", body: updated_form}}
    else
      {:error, reason} ->
        {:error, "Failed to publish WhatsApp Form: #{reason}"}
    end
  end

  @doc """
  Get a specific whatsapp form by id
  """
  @spec get_whatsapp_form_by_id(any(), %{id: String.t()}, any()) ::
          {:ok, WhatsappForm.t()} | {:error, any()}
  def get_whatsapp_form_by_id(_, %{id: id}, _) do
    WhatsappForms.get_whatsapp_form_by_id(id)
  end
end
