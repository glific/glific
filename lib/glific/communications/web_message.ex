defmodule Glific.Communications.WebMessage do
  @moduledoc """
  The web channel's message communication context — mirrors
  `Glific.Communications.GroupMessage`'s split-context shape, but for browser contacts
  connected over `GlificWeb.WebChannelSocket` instead of a BSP-backed WhatsApp group.

  Outbound send always goes through the hardcoded `Glific.Providers.Web.Message` provider
  (there is no per-organization BSP config for the web channel). Inbound messages arrive
  from `GlificWeb.WebChannel.RoomChannel`, are persisted, published to the staff inbox, and
  handed to the flow engine via the same poolboy path used for WhatsApp inbound.
  """

  require Logger
  import Ecto.Query

  alias Glific.Communications.Message, as: MessageCommunications

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Messages,
    Messages.Message,
    Partners,
    Repo,
    Templates.Blocks
  }

  @type_to_token %{
    text: :send_text,
    image: :send_image,
    audio: :send_audio,
    video: :send_video,
    document: :send_document,
    list: :send_interactive,
    quick_reply: :send_interactive,
    location_request_message: :send_interactive,
    blocks: :send_blocks
  }

  @doc """
  Send a web channel message to its receiver (a browser contact), via
  `Glific.Providers.Web.Message`.
  """
  @spec send_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_message(message, attrs) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    Logger.info(
      "Sending web message: type: '#{message.type}', contact_id: '#{message.receiver_id}', message_id: '#{message.id}'"
    )

    with {:ok, _} <-
           apply(
             Glific.Providers.Web.Message,
             @type_to_token[message.type],
             [message, attrs]
           ) do
      Communications.publish_data(message, :sent_message, message.organization_id)
      {:ok, message}
    end
  rescue
    error ->
      Glific.log_exception(error)
      log_error(message, "Could not send message to web channel contact")
  end

  @spec log_error(Message.t(), String.t()) :: {:error, String.t()}
  defp log_error(message, reason) do
    {:ok, _} = Messages.update_message(message, %{status: :error})
    {:error, reason}
  end

  @doc """
  Callback when we receive a message from a browser contact over the web channel.

  Contacts are shared across channels — this creates/reuses the contact by phone the same
  way WhatsApp inbound does, it just never touches `Contacts.set_session_status/2` (that's a
  WhatsApp session-window concept that doesn't apply to the web channel).
  """
  @spec receive_message(map(), atom()) :: :ok | {:ok, Message.t()} | {:error, String.t()}
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    {:ok, contact} =
      message_params.sender
      |> Map.put(:organization_id, organization_id)
      |> Contacts.maybe_create_contact()

    do_receive_message(contact, message_params, type)
  end

  # A `blocks_response` is a correlated reply to a specific outbound message (contract §4),
  # not a free-standing inbound message like text/media/location — it needs its own path so it
  # never falls into `receive_media/1` (the generic catch-all below), which would misinterpret
  # it as a media upload.
  @spec do_receive_message(Contact.t(), map(), atom()) ::
          :ok | {:ok, Message.t()} | {:error, String.t()}
  defp do_receive_message(contact, message_params, :blocks_response),
    do: receive_blocks_response(contact, message_params)

  defp do_receive_message(contact, message_params, type) do
    metadata = create_message_metadata(contact, message_params)

    message_params =
      message_params
      |> Map.merge(metadata)
      |> Map.merge(%{
        type: type,
        flow: :inbound,
        channel: "web",
        bsp_status: :delivered,
        status: :received
      })

    case type do
      t when t in [:text, :quick_reply, :list] -> receive_text(message_params)
      :location -> receive_location(message_params)
      _media -> receive_media(message_params)
    end

    :ok
  end

  # Acceptance order per contract §7: (1) the contact owns `message_id` and it is an unanswered
  # `:blocks` message, (2) envelope validation. Single-submit is enforced by the guarded
  # `update_all` in `mark_answered/2` — the WHERE clause re-checks "unanswered" at write time
  # and the caller acts on the returned row count, not on the earlier read, so two concurrent
  # responses to the same message can't both win.
  @spec receive_blocks_response(Contact.t(), map()) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp receive_blocks_response(contact, %{"message_id" => message_id} = message_params)
       when is_integer(message_id) do
    with {:ok, outbound} <- fetch_unanswered_blocks_message(message_id, contact),
         # `message_params` carries the Glific-internal `:sender`/`:organization_id` keys
         # (added by the caller, mirroring every other `receive_message/2` type) alongside the
         # raw wire-format string keys — strip them before validating so the inbound size cap
         # measures the response the client actually sent, not our own bookkeeping additions.
         :ok <-
           message_params
           |> Map.drop([:sender, :organization_id])
           |> Blocks.validate_response(outbound.interactive_content),
         {:ok, _count} <- mark_answered(outbound, message_params) do
      create_blocks_response_message(contact, outbound, message_params)
    end
  end

  defp receive_blocks_response(_contact, _message_params),
    do: {:error, "message_id is required"}

  @spec fetch_unanswered_blocks_message(non_neg_integer(), Contact.t()) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp fetch_unanswered_blocks_message(message_id, contact) do
    # Scoped to this contact's own outbound message: an id belonging to another contact, or one
    # that isn't a `:blocks` send, or one already answered, is indistinguishable from "not
    # found" to the caller (contract §6 security: unknown ids, duplicates, and late responses
    # are all rejected the same way).
    case Repo.get_by(Message, id: message_id, receiver_id: contact.id, type: :blocks) do
      %Message{} = message ->
        if answered?(message),
          do: {:error, "Blocks message not found or already answered"},
          else: {:ok, message}

      nil ->
        {:error, "Blocks message not found or already answered"}
    end
  end

  @spec answered?(Message.t()) :: boolean()
  defp answered?(%{interactive_content: content}), do: content["answered"] == true

  @spec mark_answered(Message.t(), map()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  defp mark_answered(outbound, message_params) do
    # `type(^merge_map, :map)` (not a pre-`Jason.encode!`'d string) is deliberate: Postgrex's
    # jsonb encoder JSON-encodes whatever Elixir term it's handed for a `:map`-typed parameter,
    # so handing it an already-encoded JSON *string* double-encodes it into a jsonb scalar
    # string. `a::jsonb || "a jsonb string"` is not an object merge — jsonb's `||` only merges
    # keys when both sides are objects, otherwise it returns an array — so a double-encoded RHS
    # silently turns "merge answered into the envelope" into "wrap the envelope and the string in
    # an array", corrupting `interactive_content`. Passing the map directly avoids that.
    merge_map = %{"answered" => true, "answer_summary" => message_params["summary"]}

    query =
      from(m in Message,
        where: m.id == ^outbound.id,
        where: m.receiver_id == ^outbound.receiver_id,
        where: m.type == :blocks,
        where:
          fragment("coalesce((?->>'answered')::boolean, false) = false", m.interactive_content),
        update: [
          set: [
            interactive_content: fragment("? || ?", m.interactive_content, type(^merge_map, :map))
          ]
        ]
      )

    case Repo.update_all(query, []) do
      {1, _} -> {:ok, 1}
      {0, _} -> {:error, "Blocks message not found or already answered"}
    end
  end

  @spec create_blocks_response_message(Contact.t(), Message.t(), map()) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp create_blocks_response_message(contact, outbound, message_params) do
    metadata = create_message_metadata(contact, message_params)

    attrs =
      Map.merge(metadata, %{
        type: :blocks_response,
        body: message_params["summary"],
        context_message_id: outbound.id,
        channel: "web",
        flow: :inbound,
        bsp_status: :delivered,
        status: :received,
        interactive_content: %{
          "type" => "blocks_response",
          "component" => message_params["component"],
          "values" => message_params["values"],
          "summary" => message_params["summary"],
          "context" => message_params["context"]
        }
      })

    case Messages.create_message(attrs) do
      {:ok, message} = result ->
        # `publish_and_process/2` fans out to the staff inbox and hands the message to the
        # flow engine (the poolboy consumer) asynchronously — it does not resolve to the
        # message itself, so the message this function returns is the one just created above,
        # not whatever `publish_and_process/2` returns.
        publish_and_process(result, contact.organization_id)
        {:ok, message}

      {:error, changeset} ->
        Glific.log_error(
          "Could not persist Blocks response: #{Glific.SafeLog.safe_inspect(changeset.errors)}"
        )

        {:error, "Could not persist Blocks response"}
    end
  end

  @spec receive_text(map()) :: Message.t() | nil
  defp receive_text(message_params) do
    message_params
    |> Messages.create_message()
    |> publish_and_process(message_params.organization_id)
  end

  # The media row and the message are created in one transaction so a failed message insert
  # cannot leave an orphaned message_media row. Repo.transaction returns {:ok, message} /
  # {:error, changeset} — exactly the shape publish_and_process/2 expects.
  @spec receive_media(map()) :: Message.t() | nil
  defp receive_media(message_params) do
    Repo.transaction(fn ->
      {:ok, media} =
        message_params
        |> Map.put_new(:flow, :inbound)
        |> Messages.create_message_media()

      case message_params |> Map.put(:media_id, media.id) |> Messages.create_message() do
        {:ok, message} -> message
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> publish_and_process(message_params.organization_id)
  end

  # A location message stores the coordinates in a separate `locations` row that references the
  # message, so the message must be created first (Location.changeset requires message_id).
  @spec receive_location(map()) :: Message.t() | nil
  defp receive_location(message_params) do
    {:ok, message} = Messages.create_message(message_params)

    message_params
    |> Map.put(:contact_id, message_params.sender_id)
    |> Map.put(:message_id, message.id)
    |> Contacts.create_location()

    publish_and_process({:ok, message}, message_params.organization_id)
  end

  @spec publish_and_process({:ok, Message.t()} | {:error, any()}, non_neg_integer()) ::
          Message.t() | nil
  defp publish_and_process(result, organization_id) do
    result
    |> publish_data(:received_message, organization_id)
    |> MessageCommunications.process_message()
  end

  @spec publish_data({:ok, Message.t()} | {:error, any()}, atom(), non_neg_integer()) ::
          Message.t() | nil
  defp publish_data({:error, changeset}, _data_type, _organization_id) do
    Glific.log_error(
      "Could not create inbound web message: #{Glific.SafeLog.safe_inspect(changeset.errors)}"
    )

    nil
  end

  defp publish_data({:ok, message}, data_type, organization_id),
    do: Communications.publish_data(message, data_type, organization_id)

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
