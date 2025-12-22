defmodule Glific.WhatsappFormsRevisions do
  @moduledoc """
   Context module for managing WhatsApp form revisions.
  """

  alias Glific.{
    Repo,
    WhatsappForms,
    WhatsappForms.WhatsappFormRevision
  }

  def save_revision(attrs, user) do
    payload = %{
      whatsapp_form_id: attrs.whatsapp_form_id,
      definition: attrs.definition,
      user_id: user.id,
      organization_id: user.organization_id
    }

    with {:ok, revision} <- create_revision(payload) do
      WhatsappForms.update_revision_number(whatsapp_form_id, revision_id)
    end
  end

  defp create_revision(attrs) do
    %WhatsappFormRevision{}
    |> WhatsappFormRevision.changeset(attrs)
    |> Repo.insert()
  end
end
