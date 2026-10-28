defmodule Glific.Communications.Message do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """
  import Ecto.Query
  require Logger

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Mails.BalanceAlertMail,
    Messages,
    Messages.Message,
    Partners,
    Processor.MessageWorker,
    Repo,
    WhatsappFormsResponses
  }

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
    list: :send_interactive,
    quick_reply: :send_interactive,
    location_request_message: :send_interactive
  }

  # One failure can arrive from several callback sources (Gupshup V2 and Meta-format V3).
  # A source earlier in this list replaces a stored failure from a later one, never the
  # reverse. Move "meta" first once every callback is V3.
  @error_source_priority ["gupshup", "meta"]

  # Error codes that need handling, by the source that sent them. Meta codes are only
  # recorded for now; map them here when moving to V3.
  @error_actions %{
    "gupshup" => %{
      1002 => :number_does_not_exist,
      471 => :rate_limit_exceeded,
      1003 => :insufficient_balance
    },
    "meta" => %{}
  }

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(Message.t(), map()) ::
          {:ok, Message.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def send_message(message, attrs \\ %{}) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    Logger.info(
      "Sending message: type: '#{message.type}', contact_id: '#{message.receiver.id}', message_id: '#{message.id}'"
    )

    case apply(message_handler(message), @type_to_token[message.type], [message, attrs]) do
      {:ok, _} ->
        :telemetry.execute(
          [:glific, :message, :sent],
          # currently we are not measuring latency
          %{duration: 1},
          %{
            type: message.type,
            sender_id: message.sender_id,
            receiver_id: message.receiver_id,
            organization_id: message.organization_id
          }
        )

        publish_message(message)

      {:error, :no_phone} ->
        log_error(message, "Contact has no WhatsApp number.")

      error ->
        error
    end
  rescue
    # An exception is thrown if there is no provider handler and/or sending the message
    # via the provider fails
    _ ->
      log_error(message, send_failure_reason(message))
  end

  # The only thing standing between a web-channel message and the organization's WhatsApp BSP.
  # The recipient is a browser visitor who has consented to be messaged on the web and, since
  # #5713, explicitly not on WhatsApp — so the channel decides the handler, never the org's
  # BSP credential.
  @spec message_handler(Message.t()) :: atom()
  defp message_handler(%Message{channel: :web}), do: Glific.Providers.Web.Message
  defp message_handler(message), do: Communications.provider_handler(message.organization_id)

  @spec send_failure_reason(Message.t()) :: String.t()
  defp send_failure_reason(%Message{channel: :web}),
    do: "Could not deliver message on the web channel"

  defp send_failure_reason(_message),
    do: "Could not send message to contact: Check Gupshup Setting"

  @spec log_error(Message.t(), String.t()) :: {:error, String.t()}
  defp log_error(message, reason) do
    message = Repo.preload(message, [:receiver])
    Messages.notify(message, reason)

    {:ok, _} = Messages.update_message(message, %{status: :error})
    {:error, reason}
  end

  @spec publish_message(Message.t()) :: {:ok, Message.t()}
  defp publish_message(message) do
    {
      :ok,
      if(message.publish?,
        do: publish_data(message, :sent_message),
        else: message
      )
    }
  end

  @doc """
  Callback when message send successfully.
  """
  @spec handle_success_response(Tesla.Env.t() | Req.Response.t(), Message.t()) ::
          {:ok, Message.t()}
  def handle_success_response(response, message) do
    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %Message{})
      |> Messages.update_message(%{
        bsp_message_id: sent_message_id(response),
        bsp_status: :enqueued,
        status: :sent,
        flow: :outbound,
        sent_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    publish_message_status(message)
    {:ok, message}
  end

  @spec sent_message_id(Tesla.Env.t() | Req.Response.t()) :: String.t() | nil
  # Gupshup V3 message API, whose body Req has already decoded.
  defp sent_message_id(%Req.Response{body: body}),
    do: get_in(body, ["messages", Access.at(0), "id"])

  # Gupshup V2 and Gupshup Enterprise, where Tesla returns the body as a raw JSON string.
  defp sent_message_id(%{body: body}), do: Jason.decode!(body)["messageId"]

  @spec build_error(any()) :: map()
  defp build_error(body) do
    cond do
      is_binary(body) -> %{message: body}
      is_map(body) -> body
      true -> %{message: Glific.SafeLog.safe_inspect(body)}
    end
  end

  @spec fetch_and_publish_message_status(String.t()) :: any()
  defp fetch_and_publish_message_status(bsp_message_id) do
    with {:ok, message} <- Repo.fetch_by(Message, %{bsp_message_id: bsp_message_id}) do
      publish_message_status(message)
    end
  end

  @spec publish_message_status(Message.t()) :: any()
  defp publish_message_status(message) do
    if is_nil(message.group_id),
      do: publish_data(message, :update_message_status)
  end

  @doc """
  Callback in case of any error while sending the message
  """
  @spec handle_error_response(Tesla.Env.t() | map(), Message.t()) :: {:error, String.t()}
  def handle_error_response(response, message) do
    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %Message{})
      |> Messages.update_message(%{
        bsp_status: :error,
        status: :sent,
        flow: :outbound,
        errors: build_error(response.body)
      })

    publish_message_status(message)

    {:error, response.body}
  end

  @doc """
  Callback to update the provider status for a message, returns whether the status changed.
  A failure from a higher priority source replaces a stored one and runs the error handling,
  but isn't a status change. `error_source` names the callback a failure came from, see
  `@error_source_priority`.
  """
  @spec update_bsp_status(String.t(), atom() | nil, map() | nil, String.t()) :: boolean()
  def update_bsp_status(bsp_message_id, bsp_status, params, error_source \\ "gupshup")

  def update_bsp_status(bsp_message_id, :error, errors, error_source) do
    errors = Map.put(errors, "source", error_source)
    changes = [bsp_status: :error, errors: errors, updated_at: DateTime.utc_now()]

    status_changed? =
      bsp_message_id
      |> status_change_query(:error)
      |> update_rows(changes)

    error_replaced? =
      not status_changed? and
        bsp_message_id
        |> error_replacement_query(error_source)
        |> update_rows(changes)

    if status_changed? or error_replaced?,
      do: publish_and_process_errors(bsp_message_id, errors)

    status_changed?
  end

  def update_bsp_status(bsp_message_id, bsp_status, _params, _error_source) do
    changes = [bsp_status: bsp_status, updated_at: DateTime.utc_now()]

    status_changed? =
      bsp_message_id
      |> status_change_query(bsp_status)
      |> update_rows(changes)

    # we are making an additional query to db to fetch message for sending message status subscription
    if status_changed?, do: fetch_and_publish_message_status(bsp_message_id)
    status_changed?
  end

  @spec update_rows(Ecto.Query.t(), keyword()) :: boolean()
  defp update_rows(query, changes) do
    {updated, _} = Repo.update_all(query, set: changes)
    updated > 0
  end

  # Gupshup can send the same status more than once (retries, and both V2 and V3 callbacks
  # for one message), so only a real change may run the status side effects
  @spec status_change_query(String.t(), atom() | nil) :: Ecto.Query.t()
  defp status_change_query(bsp_message_id, nil),
    do:
      from(m in Message,
        where: m.bsp_message_id == ^bsp_message_id and not is_nil(m.bsp_status)
      )

  defp status_change_query(bsp_message_id, bsp_status),
    do:
      from(m in Message,
        where:
          m.bsp_message_id == ^bsp_message_id and
            (is_nil(m.bsp_status) or m.bsp_status != ^bsp_status)
      )

  # A stored failure is replaced only by one from a higher priority source, so the same
  # failure from another callback, or a retry, doesn't run the error handling again
  @spec error_replacement_query(String.t(), String.t()) :: Ecto.Query.t()
  defp error_replacement_query(bsp_message_id, error_source) do
    lower_sources = lower_priority_sources(error_source)

    from(m in Message,
      where:
        m.bsp_message_id == ^bsp_message_id and m.bsp_status == ^:error and
          (is_nil(fragment("?->>'source'", m.errors)) or
             fragment("?->>'source' = ANY(?)", m.errors, ^lower_sources))
    )
  end

  @spec lower_priority_sources(String.t()) :: [String.t()]
  defp lower_priority_sources(error_source) do
    @error_source_priority
    |> Enum.drop_while(&(&1 != error_source))
    |> Enum.drop(1)
  end

  @spec publish_and_process_errors(String.t(), map()) :: any()
  defp publish_and_process_errors(bsp_message_id, errors) do
    case Repo.fetch_by(Message, %{bsp_message_id: bsp_message_id}) do
      {:ok, message} ->
        error_code = get_in(errors, ["payload", "payload", "code"])
        publish_message_status(message)
        process_errors(message, errors["source"], error_code)

      error ->
        Logger.error("Could not update message status: #{Glific.SafeLog.safe_inspect(error)}")
    end
  end

  @doc """
  Callback when we receive a message from whats app
  """
  @spec receive_message(map(), atom()) :: :ok | {:error, String.t()}
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    Logger.info("Received message: type: '#{type}', id: '#{message_params[:bsp_message_id]}'")

    {:ok, contact} =
      message_params.sender
      |> Map.put(:organization_id, organization_id)
      |> Contacts.maybe_create_contact()

    if Contacts.contact_blocked?(contact),
      do: :ok,
      else: do_receive_message(contact, message_params, type)
  end

  @spec do_receive_message(Contact.t(), map(), atom()) :: :ok | {:error, String.t()}
  defp do_receive_message(contact, message_params, type) do
    {:ok, contact} = Contacts.set_session_status(contact, :session)

    metadata = create_message_metadata(contact, message_params, type)

    message_params =
      message_params
      |> Map.merge(metadata)
      |> Map.merge(%{
        flow: :inbound,
        bsp_status: :delivered,
        status: :received
      })

    # publish a telemetry event about the message being received
    :telemetry.execute(
      [:glific, :message, :received],
      # currently we are not measuring latency
      %{duration: 1},
      metadata
    )

    cond do
      type in [:quick_reply, :list, :text] -> receive_text(message_params)
      type == :location -> receive_location(message_params)
      type == :whatsapp_form_response -> receive_whatsapp_form_response(message_params)
      true -> receive_media(message_params)
    end
  end

  # handler for receiving the text message
  @spec receive_text(map()) :: :ok
  defp receive_text(message_params) do
    message_params
    |> Messages.create_message()
    |> handle_inbound_create_result(message_params)
  end

  # handler for receiving the media (image|video|audio|document|sticker)  message
  # Both the media record and the message are created inside a single transaction so that a
  # duplicate bsp_message_id (at-least-once Gupshup delivery) does not leave an orphaned
  # message_media row: if the message insert is rolled back, the media insert is too.
  @spec receive_media(map()) :: :ok
  defp receive_media(message_params) do
    Repo.transaction(fn ->
      {:ok, message_media} =
        message_params
        |> Map.put_new(:flow, :inbound)
        |> Messages.create_message_media()

      result =
        message_params
        |> Map.put(:media_id, message_media.id)
        |> Messages.create_message()

      case result do
        {:ok, message} -> message
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> handle_inbound_create_result(message_params)
  end

  # Handles the result of creating an inbound message, with explicit deduplication logic.
  # Gupshup delivers webhooks at-least-once, so the same bsp_message_id can arrive multiple
  # times. The unique index correctly rejects the duplicate; here we just log and count it
  # instead of propagating an error through Appsignal.send_error (which raises an ErlangError).
  @spec handle_inbound_create_result(
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()},
          map()
        ) :: :ok
  defp handle_inbound_create_result({:error, changeset}, params) do
    case Keyword.get(changeset.errors, :bsp_message_id) do
      {"has already been taken", _} ->
        org_id = Map.get(params, :organization_id)
        bsp_id = Map.get(params, :bsp_message_id)

        Logger.warning(
          "Duplicate inbound message ignored: bsp_message_id=#{bsp_id}, org_id=#{org_id}"
        )

        Appsignal.increment_counter("duplicate_inbound_message", 1, %{org_id: org_id})
        :ok

      _ ->
        error("Create message error", changeset)
        :ok
    end
  end

  defp handle_inbound_create_result(result, _params) do
    result
    |> publish_data(:received_message)
    |> process_message()
  end

  # handler for receiving the location message
  @spec receive_location(map()) :: :ok
  defp receive_location(message_params) do
    {:ok, message} = Messages.create_message(message_params)

    message_params
    |> Map.put(:contact_id, message_params.sender_id)
    |> Map.put(:message_id, message.id)
    |> Contacts.create_location()

    message
    |> publish_data(:received_message)
    |> process_message()

    :ok
  end

  # The form response and its message are inserted in one transaction so a duplicate
  # bsp_message_id (Gupshup retries) rolls back the form response and its sheet-write job too.
  @spec receive_whatsapp_form_response(map()) :: :ok | {:error, any()}
  defp receive_whatsapp_form_response(%{organization_id: organization_id} = message_params) do
    Repo.transaction(fn ->
      with {:ok, form_response} <-
             WhatsappFormsResponses.create_whatsapp_form_response(message_params),
           {:ok, message} <-
             create_whatsapp_form_response_message(message_params, form_response) do
        message
      else
        {:error, %Ecto.Changeset{data: %Message{}} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback({:form_response, reason})
      end
    end)
    |> case do
      {:error, {:form_response, reason}} ->
        Logger.error(
          "Failed to create WhatsApp form response: bsp_message_id=#{message_params.bsp_message_id}, reason=#{Glific.SafeLog.safe_inspect(reason)}"
        )

        {:error, reason}

      {:ok, _message} = result ->
        Glific.Metrics.increment("WhatsApp Form Response Received", organization_id)
        handle_inbound_create_result(result, message_params)

      result ->
        handle_inbound_create_result(result, message_params)
    end
  end

  @spec create_whatsapp_form_response_message(map(), map()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  defp create_whatsapp_form_response_message(message_params, form_response) do
    attrs = %{
      flow: :inbound,
      type: :whatsapp_form_response,
      organization_id: message_params.organization_id,
      sender_id: form_response.contact_id,
      receiver_id: Partners.organization_contact_id(message_params.organization_id),
      contact_id: form_response.contact_id,
      body: "",
      whatsapp_form_response_id: form_response.id,
      bsp_message_id: message_params.bsp_message_id,
      bsp_status: :delivered,
      status: :received,
      context_id: message_params.context_id
    }

    Messages.create_message(attrs)
  end

  # preload the context message if it exists, so frontend can do the right thing
  @spec publish_data(Message.t() | {:ok, Message.t()} | {:error, any()}, atom()) ::
          Message.t() | nil
  defp publish_data({:error, error}, _data_type) do
    error("Create message error", error)
  end

  defp publish_data({:ok, message}, data_type),
    do: publish_data(message, data_type)

  defp publish_data(message, data_type) do
    message
    |> Repo.preload([:context_message, :contact])
    |> Communications.publish_data(
      data_type,
      message.organization_id
    )
    |> publish_simulator(data_type)
  end

  # check if the contact is simulator and send another subscription only for it
  @spec publish_simulator(Message.t() | nil, atom()) :: Message.t() | nil
  defp publish_simulator(message, type) when type in [:sent_message, :received_message] do
    if Contacts.simulator_contact?(message.contact.phone) do
      message_type =
        if type == :sent_message,
          do: :sent_simulator_message,
          else: :received_simulator_message

      Communications.publish_data(
        message,
        message_type,
        message.organization_id
      )
    end

    message
  end

  defp publish_simulator(message, _type), do: message

  @spec error(String.t(), any(), any()) :: nil
  defp error(error, e, r \\ nil) do
    "#{error}: #{Glific.SafeLog.safe_inspect(e)}, #{Glific.SafeLog.safe_inspect(r)}"
    |> Glific.log_error()

    nil
  end

  @spec process_message(Message.t() | nil) :: any
  defp process_message(nil), do: :ok

  defp process_message(message) do
    case MessageWorker.make_job(message) do
      {:ok, _job} -> :ok
      {:error, err} -> error("Enqueue message processing error", err)
    end
  end

  @spec process_errors(Message.t(), String.t() | nil, term()) :: any()
  defp process_errors(message, error_source, error_code) do
    @error_actions
    |> get_in([error_source, error_code])
    |> run_error_action(message)
  end

  @spec run_error_action(atom() | nil, Message.t()) :: any()
  defp run_error_action(:number_does_not_exist, message) do
    # Issue #2047 - Number does not exist in WhatsApp
    # Lets disable this contact and make it inactive
    # This is relatively common, so we don't send an email or log this error
    Contacts.number_does_not_exist(message.contact_id)
  end

  defp run_error_action(:rate_limit_exceeded, message) do
    # Issue #2049 - Organization has hit rate limit and
    # WABA is now rejecting messages
    organization = Partners.organization(message.organization_id)
    Partners.suspend_organization(organization)

    # We should send a message to ops and also email the org and glific support
    body = """
    #{organization.name} account has been suspended since it hit the WhatsApp rate limit.

    Your services will resume automatically at the start of the next day. Please be patient :)
    """

    Glific.log_error(body)
    BalanceAlertMail.rate_exceeded(organization, body)
  end

  defp run_error_action(:insufficient_balance, message) do
    # Issue #2049 - Organization has insufficient balance
    # Gupshup is now rejecting messages
    # We should send a message to ops and also email the org and glific support
    organization = Partners.organization(message.organization_id)
    Partners.suspend_organization(organization, 3)

    # We should send a message to ops and also email the org and glific support
    body = """
    #{organization.name} account has been suspended since its BSP balance is insufficient.

    Please refill your account immediately so Glific can send and receive messages on your behalf.
    """

    Glific.log_error(body)
    BalanceAlertMail.no_balance(organization, body)
  end

  defp run_error_action(nil, _message), do: nil

  @spec create_message_metadata(Contact.t(), map(), atom()) :: map()
  defp create_message_metadata(contact, message_params, type) do
    %{
      type: type,
      sender_id: contact.id,
      receiver_id: Partners.organization_contact_id(message_params.organization_id),
      organization_id: contact.organization_id
    }
  end
end
