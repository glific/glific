defmodule Glific.AI.Tools.Groups do
  @moduledoc """
  Reads about group chats: the groups this organisation manages, the phones it
  manages them through, and the polls sent into them.

  These are group conversations, not the contact collections that
  `Glific.AI.Tools.Reference` lists. They go out over a different provider path
  from ordinary messages, so a group that has gone quiet is rarely explained by
  a contact's own conversation.
  """

  import Ecto.Query

  alias Glific.{
    Groups.ContactWAGroup,
    Groups.WAGroup,
    Groups.WAGroups,
    Repo,
    WAGroup.WAMessage,
    WAManagedPhones,
    WaPoll
  }

  @behaviour Glific.AI.Tool

  @doc "Every group-chat lookup this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "list_group_chats",
        description: """
        Lists the group chats this organisation manages, with the managed phone
        each one belongs to and when it last saw traffic.

        Add `include: ["phones"]` for the managed numbers and their connection
        status: a group that has gone quiet usually has a disconnected phone.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"],
          include: [
            type: {:list, {:in, ["phones"]}},
            default: [],
            doc: ~s(Add "phones" for the managed numbers and their connection status)
          ]
        ]
      },
      %{
        name: "get_group_chat",
        description: """
        Reads one group chat: who is in it and what was said. Group messages go
        out over a different path from ordinary ones, so a question about a group
        is not answered by get_contact.

          * "messages" — what was sent in the group, newest first. A reply to a
            poll is a message carrying its answer, so this is where poll
            responses are.
          * "members" — the contacts in the group, and which are admins

        Call list_group_chats first if you only know the group's name.
        """,
        parameters: [
          wa_group_id: [
            type: :pos_integer,
            required: true,
            doc: "The group's id, from list_group_chats"
          ],
          include: [
            type: {:list, {:in, ["messages", "members"]}},
            default: ["messages"],
            doc: "What to return about the group"
          ],
          limit: [type: :pos_integer, default: 25, doc: "How many of each, at most 100"]
        ]
      },
      %{
        name: "list_polls",
        description: "Lists the polls this organisation has created for group chats.",
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  @doc "Reads one group-chat lookup: the groups, one group's messages and members, or the polls."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("list_group_chats", args) do
    groups =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0}}
      |> WAGroups.list_wa_groups()
      |> Enum.map(
        &%{
          id: &1.id,
          label: &1.label,
          bsp_id: &1.bsp_id,
          wa_managed_phone_id: &1.wa_managed_phone_id,
          last_communication_at: &1.last_communication_at
        }
      )

    {:ok, with_phones(groups, args[:include])}
  end

  def run("get_group_chat", %{wa_group_id: id} = args) do
    # Checked first: without it an unknown id, or one in another organisation,
    # answers with empty lists and the model reports a quiet group.
    with {:ok, group} <- fetch_group(id) do
      limit = min(args[:limit], 100)

      described =
        args[:include]
        |> Enum.uniq()
        |> Enum.reduce(%{wa_group_id: group.id, label: group.label}, fn
          "messages", acc -> Map.put(acc, :messages, group_messages(id, limit))
          "members", acc -> Map.put(acc, :members, members(id, limit))
        end)

      {:ok, described}
    end
  end

  def run("list_polls", args) do
    polls =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}}
      |> WaPoll.list_wa_polls()
      |> Enum.map(&%{id: &1.id, label: &1.label, poll_content: &1.poll_content})

    {:ok, polls}
  end

  @spec fetch_group(non_neg_integer()) :: {:ok, WAGroup.t()} | {:error, String.t()}
  defp fetch_group(id) do
    case Repo.fetch_by(WAGroup, %{id: id}) do
      {:ok, group} -> {:ok, group}
      {:error, _} -> {:error, "No group chat with id #{id} exists in this organisation."}
    end
  end

  @spec group_messages(non_neg_integer(), pos_integer()) :: [map()]
  defp group_messages(wa_group_id, limit) do
    WAMessage
    |> where([m], m.wa_group_id == ^wa_group_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> select([m], %{
      id: m.id,
      body: m.body,
      type: m.type,
      flow: m.flow,
      status: m.status,
      errors: m.errors,
      contact_id: m.contact_id,
      poll_id: m.poll_id,
      poll_content: m.poll_content,
      inserted_at: m.inserted_at
    })
    |> Repo.all()
  end

  @spec members(non_neg_integer(), pos_integer()) :: [map()]
  defp members(wa_group_id, limit) do
    ContactWAGroup
    |> where([c], c.wa_group_id == ^wa_group_id)
    |> limit(^limit)
    |> select([c], %{contact_id: c.contact_id, is_admin: c.is_admin})
    |> Repo.all()
  end

  @spec with_phones([map()], [String.t()]) :: [map()] | map()
  defp with_phones(groups, include) do
    if "phones" in include, do: %{groups: groups, managed_phones: managed_phones()}, else: groups
  end

  @spec managed_phones() :: [map()]
  defp managed_phones do
    %{filter: %{}, opts: %{limit: 100, offset: 0, order: :asc}}
    |> WAManagedPhones.list_wa_managed_phones()
    |> Enum.map(
      &%{
        id: &1.id,
        label: &1.label,
        phone: &1.phone,
        status: &1.status,
        last_status_checked_at: &1.last_status_checked_at
      }
    )
  end
end
