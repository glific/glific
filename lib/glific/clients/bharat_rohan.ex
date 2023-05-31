defmodule Glific.Clients.BharatRohan do
  @moduledoc """
  Custom webhook implementation specific to BharatRohan use case
  """

  alias Glific.{
    Messages
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("previous_advisories", fields) do
    Messages.list_messages(%{
      filter: %{flow_label: fields["flow_label"], contact_id: fields["contact_id"]},
      opts: %{limit: 3}
    })
    |> Enum.map(fn message ->
      Messages.create_and_send_message(%{
        body: message.body,
        flow: message.flow,
        media_id: message.media_id,
        organization_id: message.organization_id,
        receiver_id: message.receiver_id,
        sender_id: message.sender_id,
        type: message.type,
        user_id: message.user_id
      })
    end)

    %{success: true}
  end

  def webhook(_, _fields),
    do: %{}
end
