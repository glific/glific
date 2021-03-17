defmodule Glific.Clients.ReapBenefit do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{Flows.Flow, Repo}

  @doc """
  In the case of RB we retrive the flow name of the object (id any)
  and set that as the directory name
  """
  @spec gcs_params(map(), String.t()) :: {String.t(), String.t()}
  def gcs_params(media, bucket) do
    if media["flow_id"] do
      flow_name =
        Flow
        |> where([f], f.id == ^media["flow_id"])
        |> select([f], f.name)
        |> Repo.one()

      if flow_name in [nil, ""],
        do: {media["remote_name"], bucket},
        else: {flow_name <> "/" <> media["remote_name"], bucket}
    else
      {media["remote_name"], bucket}
    end
  end
end
