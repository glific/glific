defmodule Glific.Clients.Udhyam do
  @moduledoc """
  Custom implementation for Udhyam
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Clients.CommonWebhook,
    Flows.Flow,
    Repo
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("jugalbandi", fields), do: CommonWebhook.webhook("jugalbandi", fields)

  def webhook(_, _fields),
    do: %{}

  @doc """
  Tweak GCS Bucket name based Udhyam usecase
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    flow_id = media["flow_id"]

    if flow_id == 0,
      do: "Udhyam" <> "/" <> media["remote_name"],
      else: do_gcs_file_name(flow_id) <> "/" <> media["remote_name"]
  end

  @spec do_gcs_file_name(non_neg_integer()) :: String.t()
  defp do_gcs_file_name(flow_id) do
    Flow
    |> where([f], f.id == ^flow_id)
    |> select([fr], %{
      name: fr.name
    })
    |> Repo.one()
    |> then(& &1.name)
  end
end
