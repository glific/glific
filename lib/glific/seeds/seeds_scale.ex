if Code.ensure_loaded?(Faker) do
  defmodule Glific.Seeds.SeedsScale do
    @moduledoc """
    Script for populating the database at scale
    """
    alias Glific.{
      Contacts.Contact,
      Messages.Message,
      Partners,
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

    defp create_contact_entry(organization) do
      phone = EnUs.phone()

      %{
        name: Person.name(),
        phone: phone,
        bsp_status: "session_and_hsm",
        optin_time: DateTime.truncate(DateTime.utc_now(), :second),
        optout_time: nil,
        status: "valid",
        language_id: organization.default_language_id,
        organization_id: organization.id,
        last_message_at: DateTime.utc_now() |> DateTime.truncate(:second),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    end

    defp create_contact_entries(contacts_count, organization) do
      Enum.map(1..contacts_count, fn _ -> create_contact_entry(organization) end)
    end

    defp create_message(1), do: Shakespeare.as_you_like_it()
    defp create_message(2), do: Shakespeare.hamlet()
    defp create_message(3), do: Shakespeare.king_richard_iii()
    defp create_message(4), do: Shakespeare.romeo_and_juliet()

    defp create_message, do: create_message(Enum.random(1..4))

    defp create_message_entry(contact_id, sender_id, "ngo", index, organization) do
      create_message_entry(
        %{
          flow: "outbound",
          sender_id: sender_id,
          receiver_id: contact_id,
          contact_id: contact_id,
          organization_id: organization.id
        },
        index
      )
    end

    defp create_message_entry(contact_id, sender_id, "beneficiary", index, organization) do
      create_message_entry(
        %{
          flow: "inbound",
          sender_id: contact_id,
          receiver_id: sender_id,
          contact_id: contact_id,
          organization_id: organization.id
        },
        index
      )
    end

    defp create_message_entry(difference, index) do
      # random seconds in last month
      sub_time = Enum.random(((-index - 1) * 24 * 60 * 60)..(-index * 24 * 60 * 60))
      record_time = DateTime.utc_now() |> DateTime.add(sub_time)

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
    defp create_conversation(contact_id, sender_id, organization) do
      num_messages = Enum.random(1..@num_messages_per_conversation)

      for i <- 1..num_messages do
        case rem(Enum.random(1..10), 2) do
          0 ->
            create_message_entry(contact_id, sender_id, "ngo", num_messages - i + 1, organization)

          1 ->
            create_message_entry(
              contact_id,
              sender_id,
              "beneficiary",
              num_messages - i + 1,
              organization
            )
        end
      end
    end

    defp seed_contacts(contacts_count, organization) do
      # create random contacts entries
      contact_entries = create_contact_entries(contacts_count, organization)

      # seed contacts
      contact_entries
      |> Enum.chunk_every(300)
      |> Enum.map(&Repo.insert_all(Contact, &1))
    end

    defp seed_messages(organization, sender_id) do
      Repo.query!("ALTER TABLE messages DISABLE TRIGGER update_search_message_trigger;")

      # we dont need the generated dev messages
      if organization.id == 1,
        do: Repo.query!("TRUNCATE messages CASCADE;")

      # get all beneficiaries ids
      query =
        from c in Contact,
          select: c.id,
          where: c.id != ^organization.contact_id and c.organization_id == ^organization.id

      _ =
        Repo.all(query)
        |> Enum.shuffle()
        |> Enum.flat_map(&create_conversation(&1, sender_id, organization))
        # this enables us to send smaller chunks to postgres for insert
        |> Enum.chunk_every(1000)
        |> Enum.map(&Repo.insert_all(Message, &1, timeout: 120_000))

      Repo.query!("ALTER TABLE messages ENABLE TRIGGER update_search_message_trigger;")
    end

    defp seed_message_tags(organization) do
      Repo.query!("ALTER TABLE messages_tags DISABLE TRIGGER update_search_message_trigger;")

      seed_message_tags_generic(organization)

      seed_message_tags_unread(organization)

      seed_message_tags_not_responded(organization)

      Repo.query!("ALTER TABLE messages_tags ENABLE TRIGGER update_search_message_trigger;")
    end

    defp seed_message_tags_generic(organization) do
      query =
        from t in Tag,
          select: t.id,
          where:
            t.shortcode not in ["unread", "notresponded", "notreplied"] and
              t.organization_id == ^organization.id

      tag_ids = Repo.all(query) |> Enum.shuffle()

      query =
        from m in Message,
          select: m.id,
          where:
            m.organization_id == ^organization.id and
              m.message_number != 0

      _ =
        Repo.all(query)
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

    defp seed_message_tags_unread(organization) do
      query =
        from t in Tag,
          select: t.id,
          where:
            t.shortcode in ["unread", "notreplied"] and
              t.organization_id == ^organization.id

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

    defp seed_message_tags_not_responded(organization) do
      query =
        from t in Tag,
          select: t.id,
          where:
            t.shortcode in ["notresponded"] and
              t.organization_id == ^organization.id

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
      {opts, _, _} =
        System.argv()
        |> OptionParser.parse(
          switches: [organization: :integer, contacts: :integer],
          aliases: [o: :organization, c: :contacts]
        )

      opts =
        opts
        |> Keyword.put_new(:organization, 1)
        |> Keyword.put_new(:contacts, 500)

      organization = Partners.get_organization!(opts[:organization])

      # create seed for deterministic random data
      start = organization.id * 100
      :rand.seed(:exrop, {start, start + 1, start + 2})

      sender_id = organization.contact_id

      seed_contacts(opts[:contacts], organization)

      seed_messages(organization, sender_id)

      seed_message_tags(organization)

      # now execute the stored procedure to build the search index
      Repo.query!("SELECT create_search_messages(100)")

      nil
    end
  end
end
