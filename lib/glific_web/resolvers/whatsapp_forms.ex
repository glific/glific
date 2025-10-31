defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
  WhatsApp Forms Resolver which sits between the GraphQL schema and Glific WhatsApp Forms Context API.
  """

  import Ecto.Query, warn: false
  alias Glific.WhatsappForms

  def whatsapp_form(_, %{id: id}, _) do
    with {:ok, whatsapp_form} <- WhatsappForms.WhatsappForm.get_whatsapp_form_by_id(id) do
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
    WhatsappForms.update_whatsapp_form(id, params)
  end
end
