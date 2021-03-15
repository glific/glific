defmodule Glific.Clients.Tap do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Groups.ContactGroup, Groups.Group, Repo}

  @doc """
  In the case of TAP we retrive the first group the contact is in and store
  and set the remote name to be a sub-directory under that group (if one exists)
  """
  @spec gcs_params(map(), String.t()) :: {String.t(), String.t()}
  def gcs_params(media, bucket) do
    group_name =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], g in Group, on: cg.group_id == g.id)
      |> select([_c, _cg, g], g.label)
      |> order_by([_c, _cg, g], g.label)
      |> first()
      |> Repo.one()

    if is_nil(group_name),
      do: {media["remote_name"], bucket},
    else: {group_name <> "/" <> media["remote_name"], bucket}
  end
end
