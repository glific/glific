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
    Certificates.IssuedCertificate,
    Contacts,
    Contacts.Contact,
    Messages,
    Profiles,
    Repo,
    Tickets.Ticket
  }

  @behaviour Glific.AI.Tool

  @doc "Every contact lookup this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "get_contact",
        description: """
        Looks up one contact by id or phone number, with their opt-in status,
        WhatsApp session status and when they were last active.

        Phone numbers come back partially masked, so quote them only as shown and
        refer to a contact by `contact_id` rather than by phone.

        On its own this answers "who is this". Add `include` to explain how they
        got into the state they are in, asking only for what the question needs:

          * "history" — flows started, contact fields set, status changes, in order
          * "messages" — the conversation, newest first, with delivery status and errors
          * "profiles" — the profiles on this contact, when a flow acted as the wrong one
          * "tickets" — support tickets raised for them
          * "certificates" — certificates issued to them, and any failure

        For "why did this person stop getting messages", ask for history and messages.
        """,
        parameters: [
          contact_id: [type: :pos_integer, doc: "The contact's id"],
          phone: [type: :string, doc: "The contact's phone number, if the id is unknown"],
          include: [
            type: {:list, {:in, ["history", "messages", "profiles", "tickets", "certificates"]}},
            default: [],
            doc: "Extra detail to return alongside the contact"
          ],
          limit: [
            type: :pos_integer,
            default: 25,
            doc: "How many of each included list to return, at most 100"
          ]
        ]
      },
      %{
        name: "list_contacts",
        description: """
        Searches this organisation's contacts by name or phone, with their
        opt-in and WhatsApp session status. Use this when a question names a
        person but gives no id. Searching by phone still takes a full number;
        only the numbers returned are masked.

        Pass `collection_id` or `tag_id` to answer who is in a collection or
        carries a tag.
        """,
        parameters: [
          term: [type: :string, doc: "Match against name or phone number"],
          status: [type: :string, doc: ~s(Only contacts with this status, e.g. "valid")],
          collection_id: [
            type: :pos_integer,
            doc: "Only contacts in this collection, from list_reference kind \"collections\""
          ],
          tag_id: [
            type: :pos_integer,
            doc: "Only contacts carrying this tag, from list_reference kind \"tags\""
          ],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
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
      }
    ]
  end

  @doc "Reads one contact lookup: a search, one contact and its history, or the tickets raised for them."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("get_contact", args) do
    with {:ok, contact} <- find(args) do
      described = %{
        id: contact.id,
        name: contact.name,
        phone: masked_phone(contact),
        status: contact.status,
        bsp_status: contact.bsp_status,
        optin_status: contact.optin_status,
        optin_time: contact.optin_time,
        optout_time: contact.optout_time,
        last_message_at: contact.last_message_at,
        language_id: contact.language_id,
        fields: contact.fields
      }

      limit = min(args[:limit], 100)

      {:ok,
       args[:include]
       |> Enum.uniq()
       |> Enum.reduce(described, &include(&1, &2, contact, limit))}
    end
  end

  def run("list_contacts", args) do
    filter =
      %{}
      |> maybe_put(:term, args[:term])
      |> maybe_put(:status, args[:status])
      |> maybe_put(:include_groups, args[:collection_id] && [args[:collection_id]])
      |> maybe_put(:include_tags, args[:tag_id] && [args[:tag_id]])

    contacts =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> Contacts.list_contacts()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          phone: masked_phone(&1),
          status: &1.status,
          bsp_status: &1.bsp_status,
          optin_status: &1.optin_status,
          last_message_at: &1.last_message_at
        }
      )

    {:ok, contacts}
  end

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

  @spec include(String.t(), map(), Contact.t(), pos_integer()) :: map()
  defp include("history", described, contact, limit),
    do: Map.put(described, :history, history(contact.id, limit))

  defp include("messages", described, contact, limit),
    do: Map.put(described, :messages, messages(contact.id, limit))

  defp include("profiles", described, contact, limit),
    do: Map.put(described, :profiles, profiles(contact.id, limit))

  defp include("tickets", described, contact, limit),
    do: Map.put(described, :tickets, tickets_for(contact.id, limit))

  defp include("certificates", described, contact, limit),
    do: Map.put(described, :certificates, certificates(contact.id, limit))

  @spec history(non_neg_integer(), pos_integer()) :: [map()]
  defp history(contact_id, limit) do
    %{filter: %{contact_id: contact_id}, opts: %{limit: limit, offset: 0, order: :desc}}
    |> Contacts.list_contact_history()
    |> Enum.map(
      &%{
        event_type: &1.event_type,
        event_label: &1.event_label,
        event_datetime: &1.event_datetime,
        event_meta: &1.event_meta
      }
    )
  end

  @spec messages(non_neg_integer(), pos_integer()) :: [map()]
  defp messages(contact_id, limit) do
    %{filter: %{contact_id: contact_id}, opts: %{limit: limit, offset: 0, order: :desc}}
    |> Messages.list_messages()
    |> Enum.map(
      &%{
        id: &1.id,
        body: truncate(&1.body),
        type: &1.type,
        flow: &1.flow,
        status: &1.status,
        bsp_status: &1.bsp_status,
        errors: &1.errors,
        is_hsm: &1.is_hsm,
        sent_at: &1.sent_at,
        inserted_at: &1.inserted_at
      }
    )
  end

  @spec profiles(non_neg_integer(), pos_integer()) :: [map()]
  defp profiles(contact_id, limit) do
    %{filter: %{contact_id: contact_id}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> Profiles.list_profiles()
    |> Enum.map(&%{id: &1.id, name: &1.name, type: &1.type, is_default: &1.is_default})
  end

  @spec certificates(non_neg_integer(), pos_integer()) :: [map()]
  defp certificates(contact_id, limit) do
    IssuedCertificate
    |> where([c], c.contact_id == ^contact_id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> select([c], %{
      certificate_template_id: c.certificate_template_id,
      gcs_url: c.gcs_url,
      errors: c.errors,
      inserted_at: c.inserted_at
    })
    |> Repo.all()
  end

  @spec tickets_for(non_neg_integer(), pos_integer()) :: [map()]
  defp tickets_for(contact_id, limit) do
    Ticket
    |> where([t], t.contact_id == ^contact_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> select([t], %{id: t.id, body: t.body, topic: t.topic, status: t.status})
    |> Repo.all()
  end

  @body 300

  @spec truncate(String.t() | nil) :: String.t() | nil
  defp truncate(nil), do: nil

  defp truncate(text) when is_binary(text),
    do: if(String.length(text) > @body, do: String.slice(text, 0, @body) <> "…", else: text)

  @spec masked_phone(Contact.t()) :: String.t() | nil
  defp masked_phone(%Contact{phone: phone}) when phone in [nil, ""], do: nil
  defp masked_phone(%Contact{} = contact), do: Contact.populate_masked_phone(contact).masked_phone

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
