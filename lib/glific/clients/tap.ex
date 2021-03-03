defmodule Glific.Clients.Tap do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Groups.ContactGroup, Groups.Group, Repo}

  @doc false
  @spec gcs_bucket(map(), String.t()) :: String.t()
  def gcs_bucket(media, default) do
    bucket =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> where([c], c.organization_id == ^media["organization_id"])
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], g in Group, on: cg.group_id == g.id)
      |> select([_c, _cg, g], g.label)
      |> order_by([_c, _cg, g], g.label)
      |> first()
      |> Repo.one()

    if is_nil(bucket),
      do: default,
      else: bucket |> String.downcase()
  end
end
