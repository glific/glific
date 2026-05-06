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

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_message(message, attrs \\ %{}) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    Logger.info(
      "Sending message: type: '#{message.type}', contact_id: '#{message.receiver.id}', message_id: '#{message.id}'"
    )

    with {:ok, _} <-
           apply(
             Communications.provider_handler(message.organization_id),
             @type_to_token[message.type],
             [message, attrs]
           ) do
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
    end
  rescue
    # An exception is thrown if there is no provider handler and/or sending the message
    # via the provider fails
    _ ->
      log_error(message, "Could not send message to contact: Check Gupshup Setting")
  end

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
  @spec handle_success_response(Tesla.Env.t(), Message.t()) :: {:ok, Message.t()}
  def handle_success_response(response, message) do
    body = response.body |> Jason.decode!()

    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %Message{})
      |> Messages.update_message(%{
        bsp_message_id: body["messageId"],
        bsp_status: :enqueued,
        status: :sent,
        flow: :outbound,
        sent_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    publish_message_status(message)
    {:ok, message}
  end

  @spec build_error(any()) :: map()
  defp build_error(body) do
    cond do
      is_binary(body) -> %{message: body}
      is_map(body) -> body
      true -> %{message: inspect(body)}
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
  Callback to update the provider status for a message
  """
  @spec update_bsp_status(String.t(), atom(), map()) :: any()
  def update_bsp_status(bsp_message_id, :error, errors) do
    # we are making an additional query to db to fetch message for sending message status subscription
    from(m in Message, where: m.bsp_message_id == ^bsp_message_id)
    |> Repo.update_all(set: [bsp_status: :error, errors: errors, updated_at: DateTime.utc_now()])

    Repo.fetch_by(Message, %{bsp_message_id: bsp_message_id})
    |> case do
      {:ok, message} ->
        publish_message_status(message)
        process_errors(message, errors, errors["payload"]["payload"]["code"])

      error ->
        Logger.error("Could not update message status: #{inspect(error)}")
    end
  end

  def update_bsp_status(bsp_message_id, bsp_status, _params) do
    # we are making an additional query to db to fetch message for sending message status subscription
    from(m in Message, where: m.bsp_message_id == ^bsp_message_id)
    |> Repo.update_all(set: [bsp_status: bsp_status, updated_at: DateTime.utc_now()])

    fetch_and_publish_message_status(bsp_message_id)
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
    |> publish_data(:received_message)
    |> process_message()
  end

  # handler for receiving the media (image|video|audio|document|sticker)  message
  @spec receive_media(map()) :: :ok
  defp receive_media(message_params) do
    {:ok, message_media} =
      message_params
      |> Map.put_new(:flow, :inbound)
      |> Messages.create_message_media()

    {:ok, _message} =
      message_params
      |> Map.put(:media_id, message_media.id)
      |> Messages.create_message()
      |> publish_data(:received_message)
      |> process_message()

    :ok
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

  @spec receive_whatsapp_form_response(map()) :: :ok | {:error, any()}
  defp receive_whatsapp_form_response(%{organization_id: organization_id} = message_params) do
    case WhatsappFormsResponses.create_whatsapp_form_response(message_params) do
      {:ok, form_response} ->
        Glific.Metrics.increment("WhatsApp Form Response Received", organization_id)

        message_attrs = %{
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

        {:ok, message} = Messages.create_message(message_attrs)

        message
        |> publish_data(:received_message)
        |> process_message()

      {:error, reason} ->
        Logger.error("Failed to create WhatsApp form response: #{inspect(reason)}")
        {:error, reason}
    end
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

  # lets have a default timeout of 5 seconds for each call
  @timeout 5000

  @spec error(String.t(), any(), any(), list() | nil, boolean()) :: nil
  defp error(error, e, r \\ nil, stacktrace \\ nil, send_to_appsignal \\ true) do
    error = error <> ": #{inspect(e)}, #{inspect(r)}"
    Logger.error(error)

    stacktrace =
      if stacktrace == nil,
        do: Process.info(self(), :current_stacktrace) |> elem(1),
        else: stacktrace

    if send_to_appsignal do
      Appsignal.send_error(:error, error, stacktrace)
    end

    nil
  end

  @spec process_message(Message.t() | nil) :: any
  defp process_message(nil), do: :ok

  defp process_message(message) do
    # lets transfer the organization id and current user to the poolboy worker
    process_state = {
      Repo.get_organization_id(),
      Repo.get_current_user()
    }

    self = self()

    # We don't want to block the input pipeline, and we are unsure how long the consumer worker
    # will take. So we run it as a separate task
    # We will also set a short timeout for both the genserver and the poolboy transaction
    Task.start(fn ->
      :poolboy.transaction(
        Glific.Application.message_poolname(),
        fn pid ->
          try do
            GenServer.call(pid, {message, process_state, self}, @timeout)
          catch
            e, r ->
              error(
                "Poolboy genserver caught error while processing the message for flow.",
                e,
                r,
                __STACKTRACE__,
                false
              )
          end
        end
      )
    end)
  end

  @spec process_errors(Message.t(), map(), integer | nil) :: any
  defp process_errors(message, _errors, 1002) do
    # Issue #2047 - Number does not exist in WhatsApp
    # Lets disable this contact and make it inactive
    # This is relatively common, so we don't send an email or log this error
    Contacts.number_does_not_exist(message.contact_id)
  end

  defp process_errors(message, _errors, 471) do
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

  defp process_errors(message, _errors, 1003) do
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

  defp process_errors(_message, _errors, _code), do: nil

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
