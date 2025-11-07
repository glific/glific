defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
  Resolver for publishing a WhatsApp form.
  """

  alias Glific.{
    WhatsappForms,
    WhatsappForms.WhatsappForm
  }

  @doc """
  Retrieves a WhatsApp form by ID
  """
  @spec whatsapp_form(any(), %{id: non_neg_integer()}, Absinthe.Resolution.t()) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}} | {:error, any()}
  def whatsapp_form(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, whatsapp_form} <-
           WhatsappForm.get_whatsapp_form_by_id(id, user.organization_id) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    end
  end

  @doc """
  Lists all available WhatsApp form categories
  """
  @spec list_whatsapp_form_categories(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, list(String.t())}
  def list_whatsapp_form_categories(_parent, _args, _resolution) do
    WhatsappForms.list_whatsapp_form_categories()
  end

  @doc """
  Creates a WhatsApp form
  """
  @spec create_whatsapp_form(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_whatsapp_form(_, %{input: params}, _) do
    WhatsappForms.create_whatsapp_form(params)
  end

  @doc """
  Updates a WhatsApp form
  """
  @spec update_whatsapp_form(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_whatsapp_form(_, %{id: id, input: params}, _) do
    with {:ok, form} <-
           WhatsappForm.get_whatsapp_form_by_id(id, params.organization_id) do
      WhatsappForms.update_whatsapp_form(form, params)
    end
  end

  @doc """
    Publishes a WhatsApp form using its Meta Flow ID.
  """
  @spec publish_whatsapp_form(
          any(),
          %{id: non_neg_integer(), organization_id: non_neg_integer()},
          Absinthe.Resolution.t()
        ) ::
          {:ok, %{:status => String.t(), :body => Glific.WhatsappForms.WhatsappForm.t()}}
          | {:error, String.t()}
  def publish_whatsapp_form(_parent, %{id: id, organization_id: organization_id}, _) do
    with {:ok, %WhatsappForm{} = form} <-
           WhatsappForm.get_whatsapp_form_by_id(id, organization_id),
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
  @spec deactivate_wa_form(
          any(),
          %{id: non_neg_integer(), organization_id: non_neg_integer()},
          Absinthe.Resolution.t()
        ) ::
          {:ok, %{:status => String.t(), :body => Glific.WhatsappForms.WhatsappForm.t()}}
          | {:error, any()}
  def deactivate_wa_form(_parent, %{id: form_id, organization_id: organization_id}, _) do
    with {:ok, %WhatsappForm{} = form} <-
           WhatsappForm.get_whatsapp_form_by_id(form_id, organization_id),
         {:ok, updated_form} <- WhatsappForms.deactivate_wa_form(form) do
      {:ok, %{status: "success", body: updated_form}}
    else
      {:error, reason} ->
        {:error, "Failed to publish WhatsApp Form: #{reason}"}
    end
  end
end
