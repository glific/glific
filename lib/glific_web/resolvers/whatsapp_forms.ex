defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
  WhatsApp Forms Resolver which sits between the GraphQL schema and Glific WhatsApp Forms Context API.
  """

  import Ecto.Query, warn: false
  alias Glific.WhatsappForms

  @doc """
  Creates a WhatsApp form
  """
  @spec create_whatsapp_form(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_whatsapp_form(_, %{input: params}, _) do
    WhatsappForms.create_whatsapp_form(params)
  end
end
