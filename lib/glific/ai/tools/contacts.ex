defmodule Glific.AI.Tools.Contacts do
  @moduledoc """
  Reads about one contact: who they are, what has happened to them, and which
  fields this organisation records.

  Contact history is the record of flows started, fields set and status changes,
  which is how a question like *"why did this person stop receiving messages"*
  gets answered.

  Collections and tags live here too: both exist to group and label contacts,
  and other tools refer to them by id.
  """

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.ContactField,
    Groups,
    Profiles,
    Repo,
    Tags,
    Tickets.Ticket
  }

  @behaviour Glific.AI.Tool

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "get_contact",
        description: """
        Looks up one contact by id or phone number, with their opt-in status,
        WhatsApp session status and when they were last active. Use this before
        contact_history so you have the contact's id.
        """,
        parameters: [
          contact_id: [type: :pos_integer, doc: "The contact's id"],
          phone: [type: :string, doc: "The contact's phone number, if the id is unknown"]
        ]
      },
      %{
        name: "list_contacts",
        description: """
        Searches this organisation's contacts by name or phone, with their
        opt-in and WhatsApp session status. Use this when a question names a
        person but gives no id.
        """,
        parameters: [
          term: [type: :string, doc: "Match against name or phone number"],
          status: [type: :string, doc: ~s(Only contacts with this status, e.g. "valid")],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_profiles",
        description: """
        Lists the profiles attached to contacts. One phone number can carry
        several profiles, and a flow acting on the wrong one is a common cause
        of "it answered for the wrong person".
        """,
        parameters: [
          contact_id: [type: :pos_integer, doc: "Only profiles for this contact"],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_collections",
        description: """
        Lists this organisation's collections — the named sets contacts belong
        to. Triggers and broadcasts target collections, so this is how one named
        in a question is resolved to an id.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      },
      %{
        name: "list_tags",
        description: """
        Lists the tags defined in this organisation. Messages and contacts are
        tagged with these, so this is how a tag named in a question is checked
        against what exists.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      },
      %{
        name: "list_tickets",
        description: """
        Lists support tickets raised from conversations, with their topic,
        status and the contact they belong to. Use this to see what has been
        escalated to a human and whether it was resolved.
        """,
        parameters: [
          status: [type: :string, doc: ~s(Only tickets with this status, e.g. "open")],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "contact_history",
        description: """
        Lists what has happened to one contact in order: flows started, contact
        fields set, and status changes. Use this to explain why a contact is in
        the state they are in.
        """,
        parameters: [
          contact_id: [type: :pos_integer, required: true, doc: "The contact's id"],
          limit: [type: :pos_integer, default: 25, doc: "How many events to return, at most 100"]
        ]
      },
      %{
        name: "list_contact_fields",
        description: """
        Lists the contact fields defined in this organisation, with their
        shortcodes and value types. Use this before referring to a contact field
        by name, rather than assuming one exists.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
  def run("get_contact", args) do
    with {:ok, contact} <- find(args) do
      {:ok,
       %{
         id: contact.id,
         name: contact.name,
         phone: contact.phone,
         status: contact.status,
         bsp_status: contact.bsp_status,
         optin_status: contact.optin_status,
         optin_time: contact.optin_time,
         optout_time: contact.optout_time,
         last_message_at: contact.last_message_at,
         language_id: contact.language_id
       }}
    end
  end

  def run("list_contacts", args) do
    filter =
      %{}
      |> maybe_put(:term, args[:term])
      |> maybe_put(:status, args[:status])

    contacts =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> Contacts.list_contacts()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          phone: &1.phone,
          status: &1.status,
          bsp_status: &1.bsp_status,
          optin_status: &1.optin_status,
          last_message_at: &1.last_message_at
        }
      )

    {:ok, contacts}
  end

  def run("list_profiles", args) do
    filter = if args[:contact_id], do: %{contact_id: args[:contact_id]}, else: %{}

    profiles =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> Profiles.list_profiles()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          type: &1.type,
          contact_id: &1.contact_id,
          is_default: &1.is_default
        }
      )

    {:ok, profiles}
  end

  def run("list_collections", args) do
    collections =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> Groups.list_groups()
      |> Enum.map(
        &%{id: &1.id, label: &1.label, description: &1.description, group_type: &1.group_type}
      )

    {:ok, collections}
  end

  def run("list_tags", args) do
    tags =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> Tags.list_tags()
      |> Enum.map(
        &%{id: &1.id, label: &1.label, shortcode: &1.shortcode, parent_id: &1.parent_id}
      )

    {:ok, tags}
  end

  # Queried directly rather than through `Tickets.list_tickets/1`: that orders by
  # a `label` column the tickets table does not have, so any ordered call raises.
  def run("list_tickets", args) do
    tickets =
      Ticket
      |> maybe_with_status(args[:status])
      |> order_by([t], desc: t.inserted_at)
      |> limit(^min(args[:limit], 100))
      |> select([t], %{
        id: t.id,
        body: t.body,
        topic: t.topic,
        status: t.status,
        remarks: t.remarks,
        contact_id: t.contact_id,
        user_id: t.user_id,
        inserted_at: t.inserted_at
      })
      |> Repo.all()

    {:ok, tickets}
  end

  def run("contact_history", %{contact_id: contact_id} = args) do
    history =
      %{
        filter: %{contact_id: contact_id},
        opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}
      }
      |> Contacts.list_contact_history()
      |> Enum.map(
        &%{
          event_type: &1.event_type,
          event_label: &1.event_label,
          event_datetime: &1.event_datetime,
          event_meta: &1.event_meta
        }
      )

    {:ok, history}
  end

  def run("list_contact_fields", args) do
    fields =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> ContactField.list_contacts_fields()
      |> Enum.map(
        &%{name: &1.name, shortcode: &1.shortcode, value_type: &1.value_type, scope: &1.scope}
      )

    {:ok, fields}
  end

  @spec maybe_with_status(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_with_status(query, nil), do: query
  defp maybe_with_status(query, status), do: where(query, [t], t.status == ^status)

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(filter, _key, nil), do: filter
  defp maybe_put(filter, key, value), do: Map.put(filter, key, value)

  @spec find(map()) :: {:ok, Contact.t()} | {:error, String.t()}
  defp find(%{contact_id: id}), do: fetch([id: id], "id #{id}")
  defp find(%{phone: phone}), do: fetch([phone: phone], "phone #{phone}")

  defp find(_args),
    do: {:error, "Give either contact_id or phone to identify the contact."}

  @spec fetch(keyword(), String.t()) :: {:ok, Contact.t()} | {:error, String.t()}
  defp fetch(clauses, described) do
    case Repo.fetch_by(Contact, clauses) do
      {:ok, contact} -> {:ok, contact}
      {:error, _} -> {:error, "No contact with #{described} exists in this organisation."}
    end
  end
end
