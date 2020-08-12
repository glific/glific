defmodule Glific.Seeds.SeedsScale do
  @moduledoc """
  Script for populating the database at scale
  """
  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Repo,
    Tags.MessageTag,
    Tags.Tag
  }

  alias Faker.{
    Lorem.Shakespeare,
    Person,
    Phone.EnUs
  }

  import Ecto.Query

  defp create_contact_entry(language_id) do
    phone = EnUs.phone()

    %{
      name: Person.name(),
      phone: phone,
      provider_status: "session_and_hsm",
      optin_time: DateTime.truncate(DateTime.utc_now(), :second),
      optout_time: nil,
      status: "valid",
      language_id: language_id,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.truncate(:second)
    }
  end

  defp create_contact_entries(contacts_count) do
    # Get the organization
    organization = Glific.Partners.Organization |> Ecto.Query.first() |> Repo.one()

    Enum.map(1..contacts_count, fn _ -> create_contact_entry(organization.default_language_id) end)
  end

  defp create_message(1), do: Shakespeare.as_you_like_it()
  defp create_message(2), do: Shakespeare.hamlet()
  defp create_message(3), do: Shakespeare.king_richard_iii()
  defp create_message(4), do: Shakespeare.romeo_and_juliet()

  defp create_message, do: create_message(Enum.random(1..4))

  @sender_id 1
  defp create_message_entry(contact_id, "ngo", index) do
    create_message_entry(
      %{
        flow: "outbound",
        sender_id: @sender_id,
        receiver_id: contact_id,
        contact_id: contact_id
      },
      index
    )
  end

  defp create_message_entry(contact_id, "beneficiary", index) do
    create_message_entry(
      %{
        flow: "inbound",
        sender_id: contact_id,
        receiver_id: @sender_id,
        contact_id: contact_id
      },
      index
    )
  end

  defp create_message_entry(difference, index) do
    # random seconds in last month
    sub_time = Enum.random(((-index - 1) * 24 * 60 * 60)..(-index * 24 * 60 * 60))
    record_time = DateTime.utc_now() |> DateTime.add(sub_time) |> DateTime.truncate(:second)

    Map.merge(
      %{
        type: "text",
        body: create_message(),
        provider_status: "delivered",
        inserted_at: record_time,
        updated_at: record_time
      },
      difference
    )
  end

  @num_messages_per_conversation 40
  defp create_conversation(contact_id) do
    num_messages = Enum.random(1..@num_messages_per_conversation)

    for i <- 1..num_messages do
      case rem(Enum.random(1..10), 2) do
        0 -> create_message_entry(contact_id, "ngo", num_messages - i + 1)
        1 -> create_message_entry(contact_id, "beneficiary", num_messages - i + 1)
      end
    end
  end

  defp seed_contacts(contacts_count) do
    # create random contacts entries
    contact_entries = create_contact_entries(contacts_count)

    # seed contacts
    contact_entries
    |> Enum.chunk_every(300)
    |> Enum.map(&Repo.insert_all(Contact, &1))
  end

  defp seed_messages do
    Repo.query!("ALTER TABLE messages DISABLE TRIGGER update_search_message_trigger;")
    Repo.query!("TRUNCATE messages CASCADE;")

    # get all beneficiaries ids
    _ =
      Repo.all(from c in "contacts", select: c.id, where: c.id != 1)
      |> Enum.shuffle()
      |> Enum.flat_map(&create_conversation(&1))
      # this enables us to send smaller chunks to postgres for insert
      |> Enum.chunk_every(1000)
      |> Enum.map(&Repo.insert_all(Message, &1, timeout: 120_000))

    Repo.query!("ALTER TABLE messages ENABLE TRIGGER update_search_message_trigger;")
  end

  defp seed_message_tags do
    Repo.query!("ALTER TABLE messages_tags DISABLE TRIGGER update_search_message_trigger;")

    seed_message_tags_generic()

    seed_message_tags_unread()

    seed_message_tags_not_responded()

    Repo.query!("ALTER TABLE messages_tags ENABLE TRIGGER update_search_message_trigger;")
  end

  defp seed_message_tags_generic do
    query =
      from t in Tag,
        select: t.id,
        where: t.label not in ["Unread", "Not Responded", "Not Replied"]

    tag_ids = Repo.all(query) |> Enum.shuffle()

    _ =
      Repo.all(
        from m in "messages", select: m.id, where: m.receiver_id == 1 and m.message_number != 0
      )
      |> Enum.shuffle()
      |> Enum.reduce([], fn x, acc -> create_message_tag_generic(x, tag_ids, acc) end)
      |> Enum.chunk_every(1000)
      |> Enum.map(&Repo.insert_all(MessageTag, &1))
  end

  defp create_message_tag_generic(message_id, tag_ids, acc) do
    x = Enum.random(0..100)
    [t0, t1, t2] = Enum.take_random(tag_ids, 3)

    [m0, m1, m2] = [
      %{message_id: message_id, tag_id: t0},
      %{message_id: message_id, tag_id: t1},
      %{message_id: message_id, tag_id: t2}
    ]

    # seed message_tags on received messages only: 10% no tags etc
    cond do
      x < 20 -> acc
      x < 50 -> [m0 | acc]
      x < 80 -> [m0 | [m1 | acc]]
      true -> [m0 | [m1 | [m2 | acc]]]
    end
  end

  defp seed_message_tags_unread do
    query =
      from t in Tag,
        select: t.id,
        where: t.label in ["Unread", "Not replied"]

    tag_ids = Repo.all(query) |> Enum.shuffle()

    _ =
      Repo.all(
        from m in "messages", select: m.id, where: m.receiver_id == 1 and m.message_number == 0
      )
      |> Enum.shuffle()
      |> Enum.reduce([], fn x, acc -> create_message_tag_unread(x, tag_ids, acc) end)
      |> Enum.chunk_every(1000)
      |> Enum.map(&Repo.insert_all(MessageTag, &1))
  end

  defp create_message_tag_unread(message_id, tag_ids, acc) do
    x = Enum.random(0..100)
    [t0, t1] = Enum.take_random(tag_ids, 2)

    [m0, m1] = [
      %{message_id: message_id, tag_id: t0},
      %{message_id: message_id, tag_id: t1}
    ]

    # seed message_tags on received messages only: 10% no tags etc
    cond do
      x < 20 -> acc
      x < 70 -> [m0 | acc]
      true -> [m0 | [m1 | acc]]
    end
  end

  defp seed_message_tags_not_responded do
    query =
      from t in Tag,
        select: t.id,
        where: t.label in ["Not Responded"]

    tag_ids = Repo.all(query) |> Enum.shuffle()

    _ =
      Repo.all(
        from m in "messages", select: m.id, where: m.receiver_id != 1 and m.message_number == 0
      )
      |> Enum.shuffle()
      |> Enum.reduce([], fn x, acc -> create_message_tag_not_responded(x, tag_ids, acc) end)
      |> Enum.chunk_every(1000)
      |> Enum.map(&Repo.insert_all(MessageTag, &1))
  end

  defp create_message_tag_not_responded(message_id, tag_ids, acc) do
    x = Enum.random(0..100)
    [t0] = Enum.take_random(tag_ids, 1)

    m0 = %{message_id: message_id, tag_id: t0}

    # seed message_tags on received messages only: 10% no tags etc
    if x < 50,
      do: acc,
      else: [m0 | acc]
  end

  @doc false
  @spec seed_scale :: nil
  def seed_scale do
    # create seed for deterministic random data
    :rand.seed(:exrop, {101, 102, 103})

    seed_contacts(500)

    seed_messages()

    seed_message_tags()

    # now execute the stored procedure to build the search index
    Repo.query!("SELECT create_search_messages(100)")

    nil
  end
end
