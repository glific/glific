defmodule Glific.Communications.GroupMessage do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """

  require Logger

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Messages,
    Repo,
    WAGroup.WAMessage,
    WAGroup.WaReaction,
    WAManagedPhones,
    WAMessages
  }

  import Ecto.Query
  @doc false
  defmacro __using__(_opts \\ []) do
    quote do
    end
  end

  @type_to_token %{
    text: :send_text,
    image: :send_image,
    audio: :send_audio,
    video: :send_video,
    document: :send_document,
    sticker: :send_sticker,
    location_request_message: :send_interactive,
    poll: :send_poll
  }

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(WAMessage.t(), map()) :: {:ok, WAMessage.t()} | {:error, String.t()}
  def send_message(message, attrs) do
    message = Repo.preload(message, :media)

    Logger.info(
      "Sending message: type: '#{message.type}', contact_id: '#{message.contact_id}', message_id: '#{message.id}'"
    )

    with {:ok, _} <-
           apply(
             Glific.Providers.Maytapi.WAMessages,
             @type_to_token[message.type],
             [message, attrs]
           ) do
      :telemetry.execute(
        [:glific, :wa_message, :sent],
        # currently we are not measuring latency
        %{duration: 1},
        %{
          type: message.type,
          contact_id: message.contact_id,
          organization_id: message.organization_id
        }
      )

      Communications.publish_data(
        message,
        :sent_wa_group_message,
        message.organization_id
      )

      {:ok, message}
    end
  rescue
    _ ->
      log_error(message, "Could not send message to contact: Check maytapi Setting")
  end

  @doc """
  Callback when we receive a message from whatsapp group providers.

  Group inbounds are accepted only on the group's primary managed phone — any
  webhook delivered to a non-primary phone is dropped. DMs, brand-new groups
  (no `wa_group` row yet), groups with no primary set, and webhooks delivered
  to an unknown receiver all fail open and are processed normally.
  """
  @spec receive_message(map(), atom()) :: :ok | {:error, String.t()}
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    Logger.info("Received message: type: '#{type}', id: '#{message_params[:bsp_id]}'")

    cond do
      duplicate_inbound?(message_params[:bsp_id]) ->
        Logger.info(
          "Skipping inbound: bsp_id '#{message_params[:bsp_id]}' already stored in org #{organization_id} (webhook retry)"
        )

        :ok

      non_primary_receiver?(message_params, organization_id) ->
        :ok

      true ->
        {:ok, contact} =
          message_params.sender
          |> Map.put(:organization_id, organization_id)
          |> Contacts.maybe_create_contact()

        do_receive_message(contact, message_params, type)
    end
  end

  # Returns true when this inbound should be dropped because another managed
  # phone is the primary for the group it arrived on. Fails open (returns
  # false) for DMs, unknown receivers, brand-new groups, and groups with no
  # primary set; the last case is warned about loudly.
  @spec non_primary_receiver?(map(), non_neg_integer()) :: boolean()
  defp non_primary_receiver?(%{is_dm: true}, _org_id), do: false

  defp non_primary_receiver?(%{receiver: receiver}, _org_id) when receiver in [nil, ""],
    do: false

  defp non_primary_receiver?(
         %{receiver: receiver, wa_group_bsp_id: group_bsp_id},
         org_id
       ) do
    with {:ok, %{id: managed_phone_id}} <- WAManagedPhones.fetch_by_phone(receiver),
         %WAGroup{id: group_id} <- WAGroups.fetch_oldest_wa_group(group_bsp_id) do
      case primary_managed_phone_id(group_id) do
        ^managed_phone_id ->
          false

        nil ->
          Logger.warning(
            "Group #{group_bsp_id} (org #{org_id}) has no primary phone; processing inbound on #{receiver} anyway"
          )

          false

        _other ->
          Logger.info(
            "Dropping inbound on #{receiver}: a different managed phone is primary for group #{group_bsp_id} (org #{org_id})"
          )

          true
      end
    else
      _ -> false
    end
  end

  defp non_primary_receiver?(_message_params, _org_id), do: false

  @spec primary_managed_phone_id(non_neg_integer()) :: non_neg_integer() | nil
  defp primary_managed_phone_id(group_id) do
    WAGroupPhone
    |> where(
      [wgp],
      wgp.wa_group_id == ^group_id and wgp.is_primary == true and wgp.is_active == true
    )
    |> select([wgp], wgp.wa_managed_phone_id)
    |> limit(1)
    |> Repo.one()
  end

  # In multi-phone orgs Maytapi can retry the same webhook delivery; the
  # bsp_id is identical across retries, so a fetch_by it catches the duplicate.
  # Missing or nil bsp_id falls through — should not happen in practice but
  # we don't want to dedup on a nil key.
  @spec duplicate_inbound?(String.t() | nil) :: boolean()
  defp duplicate_inbound?(nil), do: false
  defp duplicate_inbound?(""), do: false

  defp duplicate_inbound?(bsp_id) do
    case Repo.fetch_by(WAMessage, %{bsp_id: bsp_id}) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Callback to update the provider status for a message
  """
  @spec update_bsp_status(String.t(), atom(), non_neg_integer()) :: any()
  def update_bsp_status(bsp_message_id, bsp_status, org_id) do
    WAMessage
    |> where([wa_msg], wa_msg.bsp_id == ^bsp_message_id and wa_msg.organization_id == ^org_id)
    |> Repo.update_all(set: [bsp_status: bsp_status, updated_at: DateTime.utc_now()])
  end

  @doc """
  Callback to update the provider error status for a message
  """
  @spec update_bsp_error_status(String.t(), map(), non_neg_integer()) :: any()
  def update_bsp_error_status(bsp_message_id, error_details, org_id) do
    WAMessage
    |> where([wa_msg], wa_msg.bsp_id == ^bsp_message_id and wa_msg.organization_id == ^org_id)
    |> Repo.update_all(
      set: [bsp_status: :error, updated_at: DateTime.utc_now(), errors: error_details]
    )
  end

  @spec log_error(WAMessage.t(), String.t()) :: {:error, String.t()}
  defp log_error(message, reason) do
    {:ok, _} = WAMessages.update_message(message, %{status: :error})
    {:error, reason}
  end

  @spec do_receive_message(Contact.t(), map(), atom()) :: :ok | {:error, String.t()}
  defp do_receive_message(contact, message_params, type) do
    {:ok, contact} = Contacts.set_session_status(contact, :session)

    metadata = create_message_metadata(contact, message_params, type)

    message_params =
      message_params
      |> Map.merge(metadata)
      |> Map.put_new(:flow, :inbound)
      |> Map.put_new(:bsp_status, :delivered)
      |> Map.put_new(:status, :received)

    # publish a telemetry event about the message being received
    :telemetry.execute(
      [:glific, :wa_message, :received],
      # currently we are not measuring latency
      %{duration: 1},
      metadata
    )

    case type do
      :text -> receive_text(message_params)
      :location -> receive_location(message_params)
      :poll -> receive_poll(message_params)
      _ -> receive_media(message_params)
    end
  end

  # handler for receiving the text message
  @spec receive_text(map()) :: :ok
  defp receive_text(message_params) do
    message_params
    |> WAMessages.create_message()
    |> Communications.publish_data(
      :received_wa_group_message,
      message_params.organization_id
    )

    :ok
  end

  # handler for receiving the media (image|video|audio|document|sticker)  message
  @spec receive_media(map()) :: :ok
  defp receive_media(message_params) do
    {:ok, message_media} =
      message_params
      |> Map.put_new(:flow, :inbound)
      |> Messages.create_message_media()

    message_params
    |> Map.put(:media_id, message_media.id)
    |> WAMessages.create_message()
    |> Communications.publish_data(
      :received_wa_group_message,
      message_params.organization_id
    )

    :ok
  end

  # handler for receiving the location message
  @spec receive_location(map()) :: :ok
  defp receive_location(message_params) do
    {:ok, message} = WAMessages.create_message(message_params)

    message_params
    |> Map.put(:contact_id, message_params.contact_id)
    |> Map.put(:wa_message_id, message.id)
    |> Contacts.create_location()

    message
    |> Communications.publish_data(:received_wa_group_message, message_params.organization_id)

    :ok
  end

  # handler for receiving the poll response
  @spec receive_poll(map()) :: :ok
  defp receive_poll(message_params) do
    message_params
    |> Map.put_new(:flow, :inbound)
    |> WAMessages.create_message()
    |> Communications.publish_data(
      :received_wa_group_message,
      message_params.organization_id
    )

    :ok
  end

  @spec create_message_metadata(Contact.t(), map(), atom()) :: map()
  defp create_message_metadata(contact, %{is_dm: is_dm} = message_params, type) do
    wa_managed_phone_id = resolve_receiver(message_params)
    wa_group_id = fetch_wa_group_id(wa_managed_phone_id, message_params)

    %{
      type: type,
      contact_id: contact.id,
      is_dm: is_dm,
      organization_id: contact.organization_id,
      wa_group_id: wa_group_id,
      wa_managed_phone_id: wa_managed_phone_id
    }
  end

  # Resolve the `receiver` phone number from the webhook into our managed
  # phone's id. If the receiver doesn't match any wa_managed_phone for the
  # org (rare — typically means the phone was removed since the webhook was
  # queued), log a warning and return nil. The message still gets stored,
  # just without phone attribution.
  @spec resolve_receiver(map()) :: non_neg_integer() | nil
  defp resolve_receiver(%{organization_id: organization_id, receiver: receiver})
       when receiver in [nil, ""] do
    Logger.warning(
      "Inbound webhook arrived without a receiver (org #{organization_id}); storing the message without phone attribution"
    )

    nil
  end

  defp resolve_receiver(%{organization_id: organization_id, receiver: receiver}) do
    case WAManagedPhones.fetch_by_phone(receiver) do
      {:ok, %{id: id}} ->
        id

      {:error, _} ->
        Logger.warning(
          "Inbound webhook receiver '#{receiver}' (org #{organization_id}) doesn't match any of our managed phones; storing the message without phone attribution"
        )

        nil
    end
  end

  @spec fetch_wa_group_id(non_neg_integer() | nil, map()) :: nil | non_neg_integer()
  defp fetch_wa_group_id(_wa_managed_phone_id, %{is_dm: true} = _message_params), do: nil

  defp fetch_wa_group_id(nil, _message_params), do: nil

  defp fetch_wa_group_id(wa_managed_phone_id, message_params) do
    # Some Maytapi webhooks (notably for brand-new groups) arrive with no
    # conversation_name. WAGroup requires a label, so fall back to the
    # bsp_id; the sync job will overwrite it once the real name is known.
    label =
      if message_params.group_name in [nil, ""],
        do: message_params.wa_group_bsp_id,
        else: message_params.group_name

    {:ok, wa_group} =
      WAGroups.maybe_create_group(%{
        organization_id: message_params.organization_id,
        wa_managed_phone_id: wa_managed_phone_id,
        bsp_id: message_params.wa_group_bsp_id,
        label: label
      })

    wa_group.id
  end

  @doc """
  handler for receiving the reaction message
  """
  @spec receive_reaction_msg(map(), non_neg_integer()) :: any()
  def receive_reaction_msg(params, org_id) do
    contact = Map.get(params, "reactorId")
    reaction = Map.get(params, "reaction")
    msg_id = Map.get(params, "msgId")
    bsp_msg_id = Map.get(params, "reactionId")
    # splitting because we are getting the contact number like 919xxxx22555@c.us this
    [phone | _] = String.split(contact, "@")

    context_message =
      WAMessage
      |> where(
        [wa_msg],
        wa_msg.bsp_id == ^msg_id and
          wa_msg.organization_id == ^org_id
      )
      |> Repo.one!()

    contact_attrs = %{
      phone: phone,
      contact_type: "WA",
      organization_id: org_id
    }

    {:ok, contact} =
      Contacts.maybe_create_contact(contact_attrs)

    {:ok, _contact_wa_group} =
      ContactWAGroups.create_contact_wa_group(%{
        contact_id: contact.id,
        wa_group_id: context_message.wa_group_id,
        organization_id: org_id
      })

    attrs =
      %{
        reaction: reaction,
        wa_message_id: context_message.id,
        contact_id: contact.id,
        bsp_id: bsp_msg_id,
        organization_id: org_id
      }

    WaReaction.create_wa_reaction(attrs)
  end

  @doc """
  Callback to update the poll response for a message
  """
  @spec update_poll_content(String.t(), map(), non_neg_integer()) :: any()
  def update_poll_content(bsp_message_id, poll_content, org_id) do
    WAMessage
    |> where([wa_msg], wa_msg.bsp_id == ^bsp_message_id and wa_msg.organization_id == ^org_id)
    |> Repo.update_all(set: [poll_content: poll_content, updated_at: DateTime.utc_now()])

    fetch_and_publish_message_status(bsp_message_id)
  end

  @spec fetch_and_publish_message_status(String.t()) :: any()
  defp fetch_and_publish_message_status(bsp_message_id) do
    with {:ok, message} <- Repo.fetch_by(WAMessage, %{bsp_id: bsp_message_id}) do
      publish_message_status(message)
    end
  end

  @spec publish_message_status(WAMessage.t()) :: any()
  defp publish_message_status(message) do
    Repo.preload(message, [:contact])
    |> Communications.publish_data(
      :update_wa_message_status,
      message.organization_id
    )
  end
end
