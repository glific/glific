defmodule Glific.Clients.Sol do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Repo}

  @doc """
  In the case of SOL we retrive the name of the contact is in and store
  and set the remote name to be a sub-directory under that name
  We add a contact id suffix to prevent name collisions
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    contact_name =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> select([c], c.name)
      |> Repo.one()

    suffix = ", #{media["contact_id"]}/#{media["remote_name"]}"

    if is_nil(contact_name) || contact_name == "",
      do: "NO NAME" <> suffix,
      else: contact_name <> suffix
  end
end
