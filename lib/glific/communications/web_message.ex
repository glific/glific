defmodule Glific.Communications.WebMessage do
  @moduledoc """
  Persists an inbound web-channel message and publishes it to the staff inbox subscription.

  Deliberately publish-only, unlike WhatsApp inbound: this never hands the message to the flow
  engine (`Communications.Message.process_message/1`). A web inbound message reaching a
  WhatsApp-only flow reply would send an unopted-in browser visitor a WhatsApp message, which is
  worse than no reply at all. Flow replies land with the "flows reply on web" ticket, which
  introduces `Providers.Web.Message` and presence-gated delivery.
  """

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Messages,
    Messages.Message,
    Partners,
    Repo
  }

  @doc """
  Callback when we receive a message from a browser contact over the web channel.

  Contacts are shared across channels — this creates/reuses the contact by phone the same way
  WhatsApp inbound does. It never calls `Contacts.set_session_status/2`: that tracks the
  WhatsApp 24-hour session window, which has no meaning for a channel with no BSP.
  """
  @spec receive_message(map(), atom()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    # Returns rather than raises throughout: the caller is a socket handler, and a raise there
    # takes the channel down instead of replying.
    with {:ok, contact} <-
           message_params.sender
           |> Map.put(:organization_id, organization_id)
           |> Contacts.maybe_create_contact() do
      message_params =
        message_params
        |> Map.merge(create_message_metadata(contact, message_params))
        |> Map.merge(%{
          type: type,
          flow: :inbound,
          channel: :web,
          bsp_status: :delivered,
          status: :received
        })

      case type do
        :text -> receive_text(message_params)
        :location -> receive_location(message_params)
        _media -> receive_media(message_params)
      end
    end
  end

  @spec receive_text(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  defp receive_text(message_params) do
    result = Messages.create_message(message_params)
    publish(result, message_params.organization_id)
    result
  end

  # One transaction, so a failed message insert cannot orphan a messages_media row.
  @spec receive_media(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  defp receive_media(message_params) do
    result =
      Repo.transaction(fn ->
        with {:ok, media} <-
               message_params
               |> Map.put_new(:flow, :inbound)
               # Already in the organization's bucket; nil would make GcsWorker re-upload it
               # into the same bucket under a second name.
               |> Map.put_new(:gcs_url, message_params[:url])
               |> Messages.create_message_media(),
             {:ok, message} <-
               message_params |> Map.put(:media_id, media.id) |> Messages.create_message() do
          message
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    publish(result, message_params.organization_id)
    result
  end

  # The message must exist before the locations row: Location.changeset requires message_id.
  @spec receive_location(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  defp receive_location(message_params) do
    with {:ok, message} <- Messages.create_message(message_params) do
      message_params
      |> Map.put(:contact_id, message_params.sender_id)
      |> Map.put(:message_id, message.id)
      |> Contacts.create_location()
      |> log_location_failure()

      publish({:ok, message}, message_params.organization_id)
      {:ok, message}
    end
  end

  # The body already carries the maps link, so this degrades the message rather than failing it.
  @spec log_location_failure({:ok, any()} | {:error, Ecto.Changeset.t()}) :: :ok
  defp log_location_failure({:error, changeset}) do
    Glific.log_error(
      "Persisted an inbound web location message but not its coordinates: " <>
        Glific.SafeLog.safe_inspect(changeset.errors)
    )

    :ok
  end

  defp log_location_failure(_result), do: :ok

  @spec publish({:ok, Message.t()} | {:error, any()}, non_neg_integer()) :: Message.t() | nil
  defp publish({:error, changeset}, _organization_id) do
    Glific.log_error(
      "Could not create inbound web message: #{Glific.SafeLog.safe_inspect(changeset.errors)}"
    )

    nil
  end

  defp publish({:ok, message}, organization_id) do
    message
    |> Repo.preload(:contact)
    |> Communications.publish_data(:received_message, organization_id)
  end

  @spec create_message_metadata(Contact.t(), map()) :: map()
  defp create_message_metadata(contact, message_params) do
    %{
      sender_id: contact.id,
      contact_id: contact.id,
      receiver_id: Partners.organization_contact_id(message_params.organization_id),
      organization_id: contact.organization_id
    }
  end
end
