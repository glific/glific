defmodule GlificWeb.Resolvers.WhatsappFormsRevisions do
  alias Glific.WhatsappFormsRevisions

  def save_revision(_, %{input: input}, %{context: %{current_user: user}}) do
    WhatsappFormsRevisions.save_revision(input, user)
  end
end
