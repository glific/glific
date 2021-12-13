defmodule Glific.Clients.Sol do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.Contacts

  @doc """
  In the case of SOL we retrive the name of the contact is in and store
  and set the remote name to be a sub-directory under that name
  We add a contact id suffix to prevent name collisions
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    contact = Contacts.get_contact!(media["contact_id"])
    city = get_in(contact.fields, ["city", "value"]) || "unknown_city"
    school_name = get_in(contact.fields, ["school_name", "value"]) || "unknown_school_name"
    student_name = get_in(contact.fields, ["contact_name", "value"]) || "unknown_student_name"

    organization_name =
      get_in(contact.fields, ["organization_name", "value"]) || "unknown_organization_name"

    folder = "#{city}/#{school_name}/#{student_name}"
    file_name = "#{contact.phone}_#{city}_#{organization_name}.png"

    "#{folder}/#{file_name}"
  end
end
