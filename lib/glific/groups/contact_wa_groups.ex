defmodule Glific.Groups.ContactWaGroups do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias __MODULE__

  alias Glific.{
    Groups.WhatsappGroup,
    Groups.ContactWAGroup,
    Repo
  }

  use Ecto.Schema
  import Ecto.Query, warn: false

  @primary_key false

  @type t() :: %__MODULE__{
          contact_wa_groups: [ContactWAGroup.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of contacts we deleted
    field(:number_deleted, :integer, default: 0)
    embeds_many(:contact_wa_groups, ContactWAGroup)
  end

  @doc """
  Returns the list of contact groups structs.

  ## Examples

      iex> list_contact_groups()
      [%ContactWAGroup{}, ...]

  """
  @spec list_contact_groups(map()) :: [ContactWAGroup.t()]
  def list_contact_groups(args) do
    IO.inspect(args)
    args
    |> Repo.list_filter_query(ContactWAGroup, &Repo.opts_with_id/2, &filter_with/2)
    |> Repo.all()
    |> IO.inspect()
  end

  # codebeat:disable[ABC, LOC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:wa_group_id, wa_group_id}, query ->
        where(query, [q], q.wa_group_id == ^wa_group_id)

      {:contact_id, contact_id}, query ->
        where(query, [q], q.contact_id == ^contact_id)

      _, query ->
        query
    end)
  end
end
