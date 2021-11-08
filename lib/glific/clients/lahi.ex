defmodule Glific.Clients.Lahi do
  @moduledoc """
    Implementation for the Lahi
  """
  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Groups.ContactGroup, Groups.Group, Repo}

  @doc """
    In the case of LAHI we retrieve image and will format the name of the image
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    contact = Contact|> where([c], c.id == ^media["contact_id"])|> Repo.one()

    phone_number = contact.phone
    datetime = Timex.now("Asia/Calcutta")
    strftime_str = Timex.format!(datetime, "%FT%T%:z", :strftime)
    phone_number <> "/" <> strftime_str <>  Path.extname(media["remote_name"]) <> "1"
  end


  @doc "webhook call to store the file in the gcs"
  @spec webhook(String.t(), map()) :: map()
  def webhook(_save_file_into_gcs, fields) do
    %{"status": true}
  end
end
