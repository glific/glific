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
  Tweak GCS Bucket name based Lahi usecase
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    flow_id = media["flow_id"]

    flow_name =
      Flow
      |> where([f], f.id == ^flow_id)
      |> select([fr], %{
        name: fr.name
      })
      |> Repo.one()
      |> then(& &1.name)

    if is_nil(flow_name),
      do: "Udhyam" <> "/" <> media["remote_name"],
      else: flow_name <> "/" <> media["remote_name"]
  end
end
