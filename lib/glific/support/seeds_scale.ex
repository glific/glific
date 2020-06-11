defmodule Glific.SeedsScale do
  @moduledoc """
  Script for populating the database at scale
  """
  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Repo,
    Tags.MessageTag
  }

  alias Faker.{
    Lorem.Shakespeare,
    Name,
    Phone.EnUs
  }

  import Ecto.Query

  defp create_contact_entry do
    phone = EnUs.phone()

    %{
      name: Name.name(),
      phone: phone,
      provider_status: "valid",
      optin_time: DateTime.truncate(DateTime.utc_now(), :second),
      optout_time: DateTime.truncate(DateTime.utc_now(), :second),
      status: "valid",
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.truncate(:second)
    }
  end

  defp create_contact_entries(contacts_count) do
    Enum.map(1..contacts_count, fn _ -> create_contact_entry() end)
  end

  defp create_message(1), do: Shakespeare.as_you_like_it()
  defp create_message(2), do: Shakespeare.hamlet()
  defp create_message(3), do: Shakespeare.king_richard_iii()
  defp create_message(4), do: Shakespeare.romeo_and_juliet()

  defp create_messages(len) do
    Enum.map(1..len, fn _ -> create_message(Enum.random(1..4)) end)
  end

  defp create_message_entry(contact_ids, message, "ngo") do
    # random seconds in last month
    sub_time = Enum.random((-31 * 24 * 60)..0)

    receiver_id = Enum.random(contact_ids)

    %{
      type: "text",
      flow: "inbound",
      body: message,
      provider_status: "delivered",
      sender_id: 1,
      receiver_id: receiver_id,
      contact_id: receiver_id,
      inserted_at: DateTime.utc_now() |> DateTime.add(sub_time) |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.add(sub_time) |> DateTime.truncate(:second)
    }
  end

  defp create_message_entry(contact_ids, message, "beneficiary") do
    # random seconds in last month
    sub_time = Enum.random((-31 * 24 * 60)..0)

    %{
      type: "text",
      flow: "inbound",
      body: message,
      provider_status: "delivered",
      sender_id: Enum.random(contact_ids),
      receiver_id: 1,
      contact_id: 1,
      inserted_at: DateTime.utc_now() |> DateTime.add(sub_time) |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.add(sub_time) |> DateTime.truncate(:second)
    }
  end

  defp create_message_entries(contact_ids, messages, "ngo") do
    Enum.map(messages, fn message -> create_message_entry(contact_ids, message, "ngo") end)
  end

  defp create_message_entries(contact_ids, messages, "beneficiary") do
    Enum.map(messages, fn message -> create_message_entry(contact_ids, message, "beneficiary") end)
  end

  defp create_message_tag(message_id, tag_ids, acc) do
    x = Enum.random(0..100)
    [t0, t1, t2, t3] = Enum.take_random(tag_ids, 4)

    cond do
      x < 25 ->
        acc

      x < 50 ->
        [%{message_id: message_id, tag_id: t0} | acc]

      x < 75 ->
        [
          %{message_id: message_id, tag_id: t0}
          | [
              %{message_id: message_id, tag_id: t1}
              | acc
            ]
        ]

      x < 90 ->
        [
          %{message_id: message_id, tag_id: t0}
          | [
              %{message_id: message_id, tag_id: t1}
              | [
                  %{message_id: message_id, tag_id: t2}
                  | acc
                ]
            ]
        ]

      true ->
        [
          %{message_id: message_id, tag_id: t0}
          | [
              %{message_id: message_id, tag_id: t1}
              | [
                  %{message_id: message_id, tag_id: t2}
                  | [
                      %{message_id: message_id, tag_id: t3}
                      | acc
                    ]
                ]
            ]
        ]
    end
  end

  defp seed_contacts(contacts_count) do
    # create random contacts entries
    contact_entries = create_contact_entries(contacts_count)

    # seed contacts
    Repo.insert_all(Contact, contact_entries)
  end

  defp seed_messages(messages_count) do
    # get all beneficiaries ids
    contact_ids =
      Glific.Contacts.list_contacts()
      |> Enum.filter(fn c -> c.id != 1 end)
      |> Enum.map(fn c -> c.id end)

    # postgresql protocol can not handle more than 65535 parameters for bulk insert
    # create list of messages
    ngo_user_messages_list = create_messages(div(messages_count, 2))
    beneficiary_user_messages_list = create_messages(div(messages_count, 2))

    # create message entries for ngo users
    ngo_user_message_entries = create_message_entries(contact_ids, ngo_user_messages_list, "ngo")

    # seed messages
    Repo.insert_all(Message, ngo_user_message_entries)

    # create message entries for beneficiaries
    beneficiary_message_entries =
      create_message_entries(contact_ids, beneficiary_user_messages_list, "beneficiary")

    # seed messages
    Repo.insert_all(Message, beneficiary_message_entries)
  end

  defp seed_message_tags do
    # seed message_tags on received messages only: 25% no tags, 25% 1 tag, 50% 2 - 4 tags, only do
    message_ids = Repo.all(from m in "messages", select: m.id, where: m.receiver_id == 1)
    tag_ids = Repo.all(from t in "tags", select: t.id)

    message_tags =
      Enum.reduce(message_ids, [], fn x, acc -> create_message_tag(x, tag_ids, acc) end)

    Repo.insert_all(MessageTag, message_tags)
  end

  @doc false
  @spec seed_scale :: nil
  def seed_scale do
    # create seed for deterministic random data
    :rand.seed(:exrop, {101, 102, 103})

    seed_contacts(500)

    seed_messages(10_000)

    seed_message_tags()

    nil
  end
end
