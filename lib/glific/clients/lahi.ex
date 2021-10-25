defmodule Glific.Clients.Lahi do
  @moduledoc """
  Custom webhook implementation specific to Lahi usecase
  """

  import Ecto.Query, warn: false

  @doc """
  Tweak GCS Bucket name based Lahi usecase
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    media["remote_name"]
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(_, _fields),
    do: %{}
end
