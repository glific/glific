defmodule Glific.Groups.ContactGroups do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias __MODULE__

  alias Glific.{
    Groups,
    Groups.ContactGroup,
    Repo
  }

  use Ecto.Schema
  import Ecto.Query, warn: false

  @primary_key false

  @type t() :: %__MODULE__{
          contact_groups: [ContactGroup.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of contacts we deleted
    field(:number_deleted, :integer, default: 0)
    embeds_many(:contact_groups, ContactGroup)
  end

  @doc """
  Returns the list of contact groups structs.

  ## Examples

      iex> list_contact_groups()
      [%ContactGroup{}, ...]

  """
  @spec list_contact_groups(map()) :: [ContactGroup.t()]
  def list_contact_groups(args) do
    args
    |> Repo.list_filter_query(ContactGroup, &Repo.opts_with_id/2, &filter_with/2)
    |> Repo.all()
  end

  # codebeat:disable[ABC, LOC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:group_id, group_id}, query ->
        where(query, [q], q.group_id == ^group_id)

      {:contact_id, contact_id}, query ->
        where(query, [q], q.contact_id == ^contact_id)

      _, query ->
        query
    end)
  end

  @doc """
  Creates and/or deletes a list of contact groups, each group attached to the same contact
  """
  @spec update_contact_groups(map()) :: ContactGroups.t()
  def update_contact_groups(
        %{contact_id: contact_id, add_group_ids: add_ids, delete_group_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    contact_groups =
      Enum.reduce(
        add_ids,
        [],
        fn group_id, acc ->
          case Groups.create_contact_group(Map.put(attrs, :group_id, group_id)) do
            {:ok, contact_group} -> [contact_group | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Groups.delete_contact_groups_by_ids(contact_id, delete_ids)

    %ContactGroups{
      number_deleted: number_deleted,
      contact_groups: contact_groups
    }
  end
end
