defmodule Glific.Clients.Udhyam do
  @moduledoc """
  Custom implementation for Udhyam
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Flows.Flow,
    Repo
  }

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
