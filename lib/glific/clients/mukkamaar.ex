defmodule Glific.Clients.MukkaMaar do
  @moduledoc """
  Custom webhook implementation specific to MukkaMaar usecase

  Nudges:
  msg_context_category
  nudge_category
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.ContactField,
    Flows.FlowContext,
    Repo
  }

  @registration_flow_id 822
  # category_1 in nudge_category is in hours while rest are in days
  @nudge_category %{
    "category_1" => 20,
    "category_2" => 2,
    "category_3" => 3
  }
  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """

  @spec webhook(String.t(), map()) :: map()
  def webhook("update_contact_categories", fields) do
    phone = String.trim(fields["phone"])

    case Repo.get_by(Contact, %{phone: phone}) do
      contact ->
        list =
          FlowContext
          |> where([fc], fc.contact_id == ^contact.id and is_nil(fc.completed_at))
          |> order_by([fc], desc: fc.id)
          # putting limit 2 as one active context will be of the current background flow
          |> limit(2)
          |> select([fc], %{id: fc.id, flow_id: fc.flow_id})
          |> Repo.all()

        set_message_category(contact, list, length(list))
    end
  end

  def webhook(_, _fields),
    do: %{}

  defp set_message_category(contact, _list, 1) do
    update_contact_field(contact, "msg_context_category", "type 3")
    |> check_nudge_category()
  end

  defp set_message_category(contact, [_current_flow, flow_stucked_on], 2) do
    updated_contact =
      if flow_stucked_on.flow_id == @registration_flow_id do
        update_contact_field(contact, "msg_context_category", "type 1")
      else
        update_contact_field(contact, "msg_context_category", "type 2")
      end

    check_nudge_category(updated_contact)
  end

  defp check_nudge_category(contact) do
    time_in_hours = Timex.diff(DateTime.utc_now(), contact.last_message_at, :hours)

    time_since_last_msg =
      if time_in_hours < 24,
        do: time_in_hours,
        else: Timex.diff(DateTime.utc_now(), contact.last_message_at, :days)

    {updated_contact, time_since_last_msg} =
      set_contact_nudge_category(contact, time_since_last_msg) |> Map.take([:fields])

    %{
      nudge_category: get_in(updated_contact, [:fields, "nudge_category", :value]),
      time: time_since_last_msg
    }
  end

  defp set_contact_nudge_category(contact, 7),
    do: {update_contact_field(contact, "nudge_category", "category 4"), 7}

  defp set_contact_nudge_category(contact, 14),
    do: {update_contact_field(contact, "nudge_category", "category 5"), 14}

  defp set_contact_nudge_category(contact, 21),
    do: {update_contact_field(contact, "nudge_category", "category 6"), 21}

  defp set_contact_nudge_category(contact, 28),
    do: {update_contact_field(contact, "nudge_category", "category 7"), 28}

  defp set_contact_nudge_category(contact, time_since_last_msg) do
    cond do
      time_since_last_msg < @nudge_category["category_1"] ->
        {update_contact_field(contact, "nudge_category", "category 1"), time_since_last_msg}

      time_since_last_msg >= 1 and time_since_last_msg < @nudge_category["category_2"] ->
        {update_contact_field(contact, "nudge_category", "category 2"), time_since_last_msg}

      time_since_last_msg >= @nudge_category["category_2"] and
          time_since_last_msg < @nudge_category["category_3"] ->
        {update_contact_field(contact, "nudge_category", "category 3"), time_since_last_msg}

      time_since_last_msg == @nudge_category["category_7"] ->
        {update_contact_field(contact, "nudge_category", "category 7"), time_since_last_msg}

      true ->
        {update_contact_field(contact, "nudge_category", "none"), "in between"}
    end
  end

  defp update_contact_field(contact, name, value) do
    contact
    |> ContactField.do_add_contact_field(name, name, value, "string")
  end
end
