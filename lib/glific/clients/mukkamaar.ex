defmodule Glific.Clients.MukkaMaar do
  @moduledoc """
  Custom webhook implementation specific to MukkaMaar usecase
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.FlowContext,
    Repo
  }

  @registration_flow_id 822
  @nudge_category %{
    # category_1 in nudge_category is in hours while rest are in days
    "category_1" => 20,
    # All other categories are in days
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

    with contact <- Repo.get_by(Contact, %{phone: phone}),
         false <- is_nil(contact) do
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
    check_nudge_category(contact, "type 3")
  end

  @spec set_message_category(Contact.t(), list(), non_neg_integer()) :: map()
  defp set_message_category(contact, [_current_flow, flow_stucked_on], 2) do
    msg_context_category =
      if flow_stucked_on.flow_id == @registration_flow_id, do: "type 1", else: "type 2"

    check_nudge_category(contact, msg_context_category)
  end

  @spec check_nudge_category(Contact.t(), String.t()) :: map()
  defp check_nudge_category(contact, msg_context_category) do
    time_in_hours = Timex.diff(DateTime.utc_now(), contact.last_message_at, :hours)

    time_since_last_msg =
      if time_in_hours < 24,
        do: time_in_hours,
        else: Timex.diff(DateTime.utc_now(), contact.last_message_at, :days)

    nudge_category = set_contact_nudge_category(time_since_last_msg)

    %{
      nudge_category: nudge_category,
      time: time_since_last_msg,
      msg_context_category: msg_context_category
    }
  end

  @spec set_contact_nudge_category(non_neg_integer()) :: String.t()
  defp set_contact_nudge_category(7), do: "category 4"

  defp set_contact_nudge_category(14), do: "category 5"

  defp set_contact_nudge_category(21), do: "category 6"

  defp set_contact_nudge_category(28), do: "category 7"

  defp set_contact_nudge_category(time_since_last_msg) do
    cond do
      time_since_last_msg < @nudge_category["category_1"] ->
        "category 1"

      time_since_last_msg >= 1 and time_since_last_msg < @nudge_category["category_2"] ->
        "category 2"

      time_since_last_msg >= @nudge_category["category_2"] and
          time_since_last_msg < @nudge_category["category_3"] ->
        "category 3"

      time_since_last_msg == @nudge_category["category_7"] ->
        "category 7"

      true ->
        "none"
    end
  end
end
