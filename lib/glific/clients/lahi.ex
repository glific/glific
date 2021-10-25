defmodule Glific.Clients.Lahi do
  @moduledoc """
    Implementation for the Lahi
  """
  import Ecto.Query, warn: false
  alias Glific.{Contacts.Contact, Groups.ContactGroup, Groups.Group, Repo}
  @doc """
    In the case of LAHI we retrive image and will fromat the name of the image
  """
  @spec gcs_file_name(map()) :: String.t()
  # IO.inspect(media)
  def gcs_file_name(media) do
    contact = Glific.Contacts.get_contact!(media["contact_id"])
    phone_number = contact.phone
    datetime = Timex.now("Asia/Calcutta")
    formated_time = Timex.format(datetime, "%FT%T%:z", :strftime)
    formated = "#{phone_number}_#{datetime}"
  end
end
