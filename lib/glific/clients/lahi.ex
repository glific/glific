defmodule Glific.Clients.Lahi do
  @moduledoc """
  Custom webhook implementation specific to Lahi usecase
  """
  alias Glific.{
    Contacts.Contact,
    Repo
  }

  import Ecto.Query, warn: false

  @doc """
  Tweak GCS Bucket name based Lahi usecase
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    contact = Contact |> where([c], c.id == ^media["contact_id"]) |> Repo.one()

    phone_number = contact.phone
    datetime = Timex.now("Asia/Calcutta")
    strftime_str = Timex.format!(datetime, "%FT%T%:z", :strftime)
    phone_number <> "/" <> strftime_str <> Path.extname(media["remote_name"]) <> "1"
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(_, _fields),
    do: %{}
end
