defmodule Glific.Messages do
  @moduledoc """
  The Messages context.
  """
  import Ecto.Query, warn: false
  use Gettext, backend: GlificWeb.Gettext

  require Logger

  alias Glific.{
    Caches,
    Communications,
    Contacts,
    Contacts.Contact,
    Conversations.Conversation,
    Flows.Broadcast,
    Flows.FlowContext,
    Flows.MessageVarParser,
    Groups.Group,
    Messages.Message,
    Messages.MessageMedia,
    Notifications,
    Partners,
    Repo,
    Tags,
    Tags.MessageTag,
    Tags.Tag,
    Templates,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates,
    Templates.SessionTemplate
  }

  @doc """
  Returns the list of filtered messages.

  ## Examples

      iex> list_messages(map())
      [%Message{}, ...]

  """
  @spec list_messages(map()) :: [Message.t()]
  def list_messages(args) do
    args
    |> Glific.add_limit()
    |> Repo.list_filter(Message, &Repo.opts_with_body/2, &filter_with/2)
    |> Enum.map(&put_clean_body/1)
  end

  @doc """
  Return the count of messages, using the same filter as list_messages
  """
  @spec count_messages(map()) :: integer
  def count_messages(args),
    do: Repo.count_filter(args, Message, &filter_with/2)

  # codebeat:disable[ABC, LOC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:sender, sender}, query ->
        from(q in query,
          join: c in assoc(q, :sender),
          where: ilike(c.name, ^"%#{sender}%")
        )

      {:receiver, receiver}, query ->
        from(q in query,
          join: c in assoc(q, :receiver),
          where: ilike(c.name, ^"%#{receiver}%")
        )

      {:contact, contact}, query ->
        from(q in query,
          join: c in assoc(q, :contact),
          where: ilike(c.name, ^"%#{contact}%")
        )

      {:either, phone}, query ->
        from(q in query,
          join: c in assoc(q, :contact),
          where: ilike(c.phone, ^"%#{phone}%")
        )

      {:user, user}, query ->
        from(q in query,
          join: c in assoc(q, :user),
          where: ilike(c.name, ^"%#{user}%")
        )

      {:tags_included, tags_included}, query ->
        message_ids =
          MessageTag
          |> where([p], p.tag_id in ^tags_included)
          |> select([p], p.message_id)
          |> Repo.all()

        query |> where([m], m.id in ^message_ids)

      {:tags_excluded, tags_excluded}, query ->
        message_ids =
          MessageTag
          |> where([p], p.tag_id in ^tags_excluded)
          |> select([p], p.message_id)
          |> Repo.all()

        query |> where([m], m.id not in ^message_ids)

      {:bsp_status, bsp_status}, query ->
        from(q in query, where: q.bsp_status == ^bsp_status)

      {:flow_label, flow_label}, query ->
        from(q in query, where: q.flow_label == ^flow_label)

      {:flow_id, flow_id}, query ->
        from(q in query, where: q.flow_id == ^flow_id)

      {:contact_id, contact_id}, query ->
        from(q in query, where: q.contact_id == ^contact_id)

      {:types, types}, query ->
        from(q in query, where: q.type in ^types)

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single message.

  Raises `Ecto.NoResultsError` if the Message does not exist.

  ## Examples

      iex> get_message!(123)
      %Message{}

      iex> get_message!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message!(integer) :: Message.t()
  def get_message!(id), do: Repo.get!(Message, id) |> put_clean_body()

  @doc """
  Creates a message.

  ## Examples

      iex> create_message(%{field: value})
      {:ok, %Message{}}

      iex> create_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs) do
    attrs =
      %{flow: :inbound, status: :enqueued}
      |> Map.merge(attrs)
      |> parse_message_vars()
      |> put_contact_id()
      |> put_clean_body()

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert(
      returning: [:message_number, :session_uuid, :context_message_id],
      timeout: 45_000
    )
  end

  @spec put_contact_id(map()) :: map()
  defp put_contact_id(%{flow: :inbound} = attrs),
    do: Map.put(attrs, :contact_id, attrs[:sender_id])

  defp put_contact_id(%{flow: :outbound} = attrs),
    do: Map.put(attrs, :contact_id, attrs[:receiver_id])

  defp put_contact_id(attrs), do: attrs

  @spec put_clean_body(map()) :: map()
  # sometimes we get no body, so we need to ensure we set to null for text type
  # Issue #2798
  defp put_clean_body(%{body: nil, type: :text} = attrs),
    do:
      attrs
      |> Map.put(:body, "")
      |> Map.put(:clean_body, "")

  defp put_clean_body(%{body: body} = attrs),
    do: Map.put(attrs, :clean_body, Glific.string_clean(body))

  defp put_clean_body(attrs), do: attrs

  @doc """
  Updates a message.

  ## Examples

      iex> update_message(message, %{field: new_value})
      {:ok, %Message{}}

      iex> update_message(message, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message.

  ## Examples

      iex> delete_message(message)
      {:ok, %Message{}}

      iex> delete_message(message)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message(Message.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def delete_message(%Message{} = message) do
    # check if there is a message media object if so, delete it
    if message.media_id,
      do:
        message.media_id
        |> get_message_media!()
        |> delete_message_media()

    Repo.delete(message)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message changes.

  ## Examples

      iex> change_message(message)
      %Ecto.Changeset{data: %Message{}}

  """
  @spec change_message(Message.t(), map()) :: Ecto.Changeset.t()
  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  @doc false
  @spec create_and_send_message(map()) :: {:ok, Message.t()} | {:error, atom() | String.t()}
  def create_and_send_message(%{body: body, type: :text} = _attrs) when body in ["", nil],
    do: {:error, "Could not send message with empty body"}

  def create_and_send_message(%{receiver_id: receiver_id} = attrs) do
    contact = Contacts.get_contact(receiver_id)

    if contact do
      attrs = Map.put(attrs, :receiver, contact)
      ## we need to clean this code in the future.
      attrs = check_for_interactive(attrs, contact.language_id)

      check_for_hsm_message(attrs, contact)
    else
      {:error, "Receiver does not exist"}
    end
  end

  @spec check_for_interactive(map(), non_neg_integer()) :: map()
  defp check_for_interactive(
         %{flow_id: flow_id, interactive_template_id: _interactive_template_id} = attrs,
         _language_id
       )
       when flow_id not in [nil, ""],
       do: attrs

  defp check_for_interactive(
         %{interactive_template_id: interactive_template_id} = attrs,
         language_id
       ) do
    {:ok, interactive_template} = Repo.fetch(InteractiveTemplate, interactive_template_id)

    # Check if this is coming form a flow
    {interactive_content, body, media_id} =
      if attrs[:interactive_content] in [nil, %{}] do
        InteractiveTemplates.formatted_data(interactive_template, language_id)
      else
        {attrs[:interactive_content], attrs[:body], attrs[:media_id]}
      end

    Map.merge(attrs, %{
      body: body,
      interactive_content: interactive_content,
      type: interactive_content["type"],
      media_id: media_id
    })
  end

  defp check_for_interactive(attrs, _language_id), do: attrs

  @doc false
  @spec check_for_hsm_message(map(), Contact.t()) ::
          {:ok, Message.t()} | {:error, atom() | String.t()}
  defp check_for_hsm_message(attrs, contact) do
    if Map.has_key?(attrs, :template_id) && Map.get(attrs, :is_hsm) do
      attrs
      ## We need to fix this inconsistency in the parameter and params name
      |> Map.put(:parameters, attrs.params)
      |> create_and_send_hsm_message()
    else
      Contacts.can_send_message_to?(contact, Map.get(attrs, :is_hsm, false), attrs)
      |> do_send_message(attrs)
    end
  end

  @doc false
  @spec do_send_message({:ok | :error, any()}, map()) ::
          {:ok, Message.t()} | {:error, atom() | String.t()}
  defp do_send_message(
         {:ok, _} = _is_valid_contact,
         %{organization_id: organization_id} = attrs
       ) do
    {:ok, message} =
      attrs
      |> Map.put_new(:type, :text)
      |> Map.merge(%{
        sender_id: Partners.organization_contact_id(organization_id),
        flow: :outbound
      })
      |> create_message()

    result = Communications.Message.send_message(message, attrs)

    if attrs[:is_hsm] && attrs[:button_type] == :whatsapp_form do
      Glific.Metrics.increment("WhatsApp Form Dispatched", organization_id)
    end

    result
  end

  defp do_send_message({:error, reason}, attrs) do
    notify(attrs, reason)
    {:error, reason}
  end

  @doc """
  Create and insert a notification for this error when sending a message.
  Add as much detail, so we can reverse-engineer why the sending failed.
  """
  @spec notify(map(), String.t()) :: nil
  def notify(attrs, reason \\ "Cannot send the message to the contact.") do
    contact =
      if is_nil(Map.get(attrs, :receiver, nil)),
        do: Contacts.get_contact!(attrs.receiver_id),
        else: attrs.receiver

    Logger.error(
      "Could not send message: contact: #{contact.id}, message: '#{Map.get(attrs, :id)}', reason: #{reason}"
    )

    {:ok, _} =
      Notifications.create_notification(%{
        category: "Message",
        message: reason,
        severity: Notifications.types().warning,
        organization_id: attrs.organization_id,
        entity: %{
          id: contact.id,
          name: contact.name,
          phone: contact.phone,
          bsp_status: contact.bsp_status,
          status: contact.status,
          last_message_at: contact.last_message_at,
          is_hsm: Map.get(attrs, :is_hsm),
          flow_id: Map.get(attrs, :flow_id),
          group_id: Map.get(attrs, :group_id)
        }
      })

    nil
  end

  @spec parse_message_vars(map()) :: map()
  defp parse_message_vars(attrs) do
    message_vars =
      if is_integer(attrs[:receiver_id]) or is_binary(attrs[:receiver_id]),
        do: %{"contact" => Contacts.get_contact_field_map(attrs.receiver_id)},
        else: %{}

    parse_text_message_fields(attrs, message_vars)
    |> parse_media_message_fields(message_vars)
    |> parse_interactive_message_fields(message_vars)
  end

  @spec parse_text_message_fields(map(), map()) :: map()
  defp parse_text_message_fields(attrs, message_vars) do
    if is_binary(attrs[:body]) do
      {:ok, msg_uuid} = Ecto.UUID.cast(:crypto.hash(:md5, attrs.body))

      attrs
      |> Map.merge(%{
        uuid: attrs[:uuid] || msg_uuid,
        body: MessageVarParser.parse(attrs.body, message_vars)
      })
    else
      attrs
    end
  end

  @spec parse_media_message_fields(map(), map()) :: map()
  defp parse_media_message_fields(attrs, message_vars) do
    ## if message media is present change the variables in caption
    if is_integer(attrs[:media_id]) or is_binary(attrs[:media_id]) do
      message_media = get_message_media!(attrs.media_id)

      message_media
      |> update_message_media(%{
        caption: MessageVarParser.parse(message_media.caption, message_vars)
      })
    end

    attrs
  end

  @spec parse_interactive_message_fields(map(), map()) :: map()
  defp parse_interactive_message_fields(attrs, message_vars) do
    attrs[:interactive_content]
    |> MessageVarParser.parse_map(message_vars)
    |> InteractiveTemplates.clean_template_title()
    |> then(&Map.merge(attrs, %{interactive_content: &1}))
  end

  @doc false
  @spec create_and_send_otp_verification_message(Contact.t(), String.t()) ::
          {:ok, Message.t()}
  def create_and_send_otp_verification_message(contact, otp) do
    case Contacts.can_send_message_to?(contact, false) do
      {:ok, _} -> create_and_send_otp_session_message(contact, otp)
      _ -> create_and_send_otp_template_message(contact, otp)
    end
  end

  @doc false
  @spec create_and_send_otp_session_message(Contact.t(), String.t()) ::
          {:ok, Message.t()}
  def create_and_send_otp_session_message(contact, otp) do
    body =
      "#{otp} is your verification code. For your security, do not share this code."

    send_default_message(contact, body)
  end

  @doc false
  @spec create_and_send_otp_template_message(Contact.t(), String.t()) ::
          {:ok, Message.t()}
  def create_and_send_otp_template_message(contact, otp) do
    # fetch session template by shortcode "verification"
    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{
        shortcode: "verify_otp",
        is_hsm: true,
        organization_id: contact.organization_id
      })

    parameters = [otp]

    %{template_id: session_template.id, receiver_id: contact.id, parameters: parameters}
    |> create_and_send_hsm_message()
  end

  @doc """
  Send a session template to the specific contact. This is typically used in automation
  """
  @spec create_and_send_session_template(String.t(), integer) :: {:ok, Message.t()}
  def create_and_send_session_template(template_id, receiver_id) when is_binary(template_id),
    do: create_and_send_session_template(String.to_integer(template_id), receiver_id)

  @spec create_and_send_session_template(integer, integer) :: {:ok, Message.t()}
  def create_and_send_session_template(template_id, receiver_id) when is_integer(template_id) do
    {:ok, session_template} = Repo.fetch(SessionTemplate, template_id)

    create_and_send_session_template(
      session_template,
      %{receiver_id: receiver_id}
    )
  end

  @spec create_and_send_session_template(SessionTemplate.t() | map(), map()) :: {:ok, Message.t()}
  def create_and_send_session_template(session_template, args) do
    message_params = %{
      body: session_template.body,
      type: session_template.type,
      template_id: session_template.id,
      media_id: session_template.message_media_id,
      sender_id: Partners.organization_contact_id(session_template.organization_id),
      receiver_id: args[:receiver_id],
      send_at: args[:send_at],
      flow_id: args[:flow_id],
      message_broadcast_id: args[:message_broadcast_id],
      uuid: args[:uuid],
      is_hsm: Map.get(args, :is_hsm, false),
      flow_label: args[:flow_label],
      organization_id: session_template.organization_id,
      params: args[:params]
    }

    create_and_send_message(message_params)
  end

  @spec fetch_language_specific_template(map(), integer()) :: tuple()
  defp fetch_language_specific_template(session_template, id) do
    contact = Contacts.get_contact!(id)

    with true <- session_template.language_id != contact.language_id,
         translation <- session_template.translations[Integer.to_string(contact.language_id)],
         false <- is_nil(translation),
         "APPROVED" <- translation["status"] do
      template =
        session_template
        |> Map.from_struct()
        |> Map.put(:body, translation["body"])
        |> Map.put(:uuid, translation["uuid"])

      {true, template}
    else
      _ -> {false, session_template}
    end
  end

  @spec hsm_message_params(SessionTemplate.t(), map(), boolean()) :: map()
  defp hsm_message_params(
         session_template,
         %{template_id: template_id, receiver_id: receiver_id, parameters: parameters} = attrs,
         is_translated
       ) do
    # sending default media when media type is not defined
    media_id = Map.get(attrs, :media_id, session_template.message_media_id)

    updated_template =
      session_template
      |> Templates.parse_buttons(is_translated, session_template.has_buttons)
      |> parse_template_vars(parameters)

    parsed_body =
      session_template
      |> parse_template_vars(parameters)
      |> Map.get(:body)

    %{
      parsed_body: parsed_body,
      body: updated_template.body,
      type: updated_template.type,
      is_hsm: updated_template.is_hsm,
      organization_id: session_template.organization_id,
      sender_id: Partners.organization_contact_id(session_template.organization_id),
      receiver_id: receiver_id,
      template_uuid: session_template.uuid,
      template_id: template_id,
      template_type: session_template.type,
      has_buttons: session_template.has_buttons,
      button_type: session_template.button_type,
      params: parameters,
      media_id: media_id,
      is_optin_flow: Map.get(attrs, :is_optin_flow, false),
      flow_label: Map.get(attrs, :flow_label, ""),
      message_broadcast_id: Map.get(attrs, :message_broadcast_id, nil),
      user_id: attrs[:user_id],
      flow_id: attrs[:flow_id],
      send_at: attrs[:send_at]
    }
  end

  @doc """
  Send a hsm template message to the specific contact.
  """
  @spec create_and_send_hsm_message(map()) ::
          {:ok, Message.t()} | {:error, String.t()}
  def create_and_send_hsm_message(
        %{template_id: template_id, receiver_id: receiver_id, parameters: parameters} = attrs
      ) do
    contact_vars = %{"contact" => Contacts.get_contact_field_map(attrs.receiver_id)}

    parsed_params =
      Enum.map(parameters, &MessageVarParser.parse(&1, contact_vars))
      |> Enum.map(&(String.split(&1) |> Enum.join(" ") |> String.replace("\n", "")))

    ## As per the WhatsApp policy the params in an HSM can not have more then two
    ## consecutive spaces and a new line.
    parsed_params = Enum.map(parsed_params, &Enum.join(String.split(&1), " "))

    attrs = Map.put(attrs, :parameters, parsed_params)

    Repo.fetch(SessionTemplate, template_id)
    |> case do
      {:ok, template} ->
        media_id = Map.get(attrs, :media_id, nil)

        {is_translated, session_template} =
          fetch_language_specific_template(template, receiver_id)

        with true <- session_template.number_parameters == length(parameters),
             {"type", true} <- {"type", session_template.type == :text || media_id != nil} do
          # Passing uuid to save db call when sending template via provider
          message_params = hsm_message_params(session_template, attrs, is_translated)

          receiver_id
          |> Glific.Contacts.get_contact!()
          |> Contacts.can_send_message_to?(true, attrs)
          |> do_send_message(message_params)
        else
          false ->
            {:error,
             dgettext(
               "errors",
               "Please provide the right number of parameters for the template."
             )}

          {"type", false} ->
            {:error, dgettext("errors", "Please provide media for media template.")}
        end

      {:error, error} ->
        {:error,
         "Not able to fetch the template with id #{template_id}. ERROR: #{inspect(error)}"}
    end
  end

  @doc false
  @spec parse_template_vars(SessionTemplate.t(), [String.t()]) :: SessionTemplate.t()
  def parse_template_vars(%{number_parameters: np} = session_template, _parameters)
      when is_nil(np) or np <= 0,
      do: session_template

  def parse_template_vars(session_template, parameters) do
    parameters_map =
      1..session_template.number_parameters
      |> Enum.zip(parameters)

    updated_body =
      Enum.reduce(parameters_map, session_template.body, fn {key, value}, body ->
        String.replace(body, "{{#{key}}}", value)
      end)

    session_template
    |> Map.merge(%{body: updated_body})
  end

  @doc false
  @spec create_and_send_message_to_contacts(map(), [], atom()) :: {:ok, list()}
  def create_and_send_message_to_contacts(message_params, contact_ids, type) do
    contact_ids =
      contact_ids
      |> Enum.reduce([], fn contact_id, contact_ids ->
        message_params = Map.put(message_params, :receiver_id, contact_id)

        result =
          if type == :session,
            do: create_and_send_message(message_params),
            else: create_and_send_hsm_message(message_params)

        case result do
          {:ok, message} ->
            [message.contact_id | contact_ids]

          {:error, _} ->
            contact_ids
        end
      end)

    {:ok, contact_ids}
  end

  @doc """
  Record a message sent to a group in the message table. This message is actually not
  sent, but is used for display purposes in the group listings
  """
  @spec create_group_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_group_message(attrs) do
    # We first need to just create a meta level group message
    organization_id = Repo.get_organization_id()
    sender_id = Partners.organization_contact_id(organization_id)

    attrs
    |> Map.merge(%{
      organization_id: organization_id,
      sender_id: sender_id,
      receiver_id: sender_id,
      contact_id: sender_id,
      flow: :outbound
    })
    |> create_message()
    |> case do
      {:ok, message} ->
        group_message_subscription(message)
        {:ok, message}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec group_message_subscription(Message.t()) :: any()
  defp group_message_subscription(message) do
    Communications.publish_data(
      message,
      :sent_group_message,
      message.organization_id
    )
  end

  @doc """
  Create and send message to all contacts of a group
  """
  @spec create_and_send_message_to_group(map(), Group.t(), atom()) ::
          {:ok, any()} | {:error, any()}
  def create_and_send_message_to_group(message_params, group, _type) do
    message_params =
      message_params
      |> Map.merge(%{group_id: group.id})
      # this is an exception because of an inconsistency with the key name
      |> Map.put_new(:parameters, message_params[:params])

    {:ok, group_message} =
      if message_params[:is_hsm] in [nil, false],
        do: create_group_message(message_params |> Map.put_new(:type, :text)),
        else:
          message_params
          |> Map.put_new(:type, :text)
          |> Map.put(
            :body,
            "Sending HSM template #{message_params.template_id}, params: #{message_params.parameters}"
          )
          |> create_group_message()

    {:ok, message_broadcast} =
      Broadcast.broadcast_message_to_group(group_message, [group.id], message_params)

    {:ok, Broadcast.get_broadcast_contact_ids(message_broadcast)}
  end

  @doc """
  Check if the tag is present in message
  """
  @spec tag_in_message?(Message.t(), integer) :: boolean
  def tag_in_message?(message, tag_id) do
    Ecto.assoc_loaded?(message.tags) &&
      Enum.find(message.tags, fn t -> t.id == tag_id end) != nil
  end

  @doc """
  Returns the list of message media.

  ## Examples

      iex> list_messages_media(map())
      [%MessageMedia{}, ...]

  """
  @spec list_messages_media(map()) :: [MessageMedia.t()]
  def list_messages_media(args \\ %{}) do
    args
    |> Glific.add_limit()
    |> Repo.list_filter(MessageMedia, &opts_media_with/2, &filter_media_with/2)
  end

  defp filter_media_with(query, _), do: query

  defp opts_media_with(query, opts) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        query |> order_by([m], {^order, fragment("lower(?)", m.caption)})

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of messages, using the same filter as list_messages
  """
  @spec count_messages_media(map()) :: integer
  def count_messages_media(args \\ %{}),
    do: Repo.count_filter(args, MessageMedia, &filter_media_with/2)

  @doc """
  Gets a single message media.

  Raises `Ecto.NoResultsError` if the Message media does not exist.

  ## Examples

      iex> get_message_media!(123)
      %MessageMedia{}

      iex> get_message_media!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message_media!(integer) :: MessageMedia.t()
  def get_message_media!(id), do: Repo.get!(MessageMedia, id)

  @doc """
  Creates a message media.

  ## Examples

      iex> create_message_media(%{field: value})
      {:ok, %MessageMedia{}}

      iex> create_message_media(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message_media(map()) :: {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  def create_message_media(attrs \\ %{}) do
    %MessageMedia{}
    |> MessageMedia.changeset(attrs)
    |> check_changeset(attrs)
  end

  @spec check_changeset(Ecto.Changeset.t(), map()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  defp check_changeset(changeset, attrs) do
    has_no_errors = Enum.empty?(changeset.errors)
    if has_no_errors, do: do_create_message_media(changeset, attrs), else: {:error, changeset}
  end

  @spec do_create_message_media(Ecto.Changeset.t(), map()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  defp do_create_message_media(changeset, attrs) do
    caption = Map.get(attrs, :caption, nil)

    message_media =
      MessageMedia
      |> where([mm], mm.url == ^attrs.url)
      |> add_caption(caption)
      |> where([mm], mm.organization_id == ^attrs.organization_id)
      |> limit(1)
      |> Repo.one()

    case message_media do
      %MessageMedia{} = message_media -> {:ok, message_media}
      nil -> Repo.insert(changeset)
    end
  end

  defp add_caption(query, caption) when is_nil(caption), do: query

  defp add_caption(query, caption) do
    query
    |> where([mm], mm.caption == ^caption)
  end

  @doc """
  Updates a message media.

  ## Examples

      iex> update_message_media(message_media, %{field: new_value})
      {:ok, %MessageMedia{}}

      iex> update_message_media(message_media, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message_media(MessageMedia.t(), map()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  def update_message_media(%MessageMedia{} = message_media, attrs) do
    message_media
    |> MessageMedia.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message media.

  ## Examples

      iex> delete_message_media(message_media)
      {:ok, %MessageMedia{}}

      iex> delete_message_media(message_media)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message_media(MessageMedia.t()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  def delete_message_media(%MessageMedia{} = message_media) do
    Repo.delete(message_media)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message media changes.

  ## Examples

      iex> change_message_media(message_media)
      %Ecto.Changeset{data: %MessageMedia{}}

  """
  @spec change_message_media(MessageMedia.t(), map()) :: Ecto.Changeset.t()
  def change_message_media(%MessageMedia{} = message_media, attrs \\ %{}) do
    MessageMedia.changeset(message_media, attrs)
  end

  defp do_list_conversations(query, args, false = _count) do
    query
    |> preload([
      :contact,
      :sender,
      :receiver,
      :context_message,
      :tags,
      :user,
      :media,
      :whatsapp_form_response
    ])
    |> Repo.all()
    |> make_conversations()
    |> add_empty_conversations(args)
  end

  defp do_list_conversations(query, _args, true = _count) do
    query
    |> select([m], m.contact_id)
    |> distinct(true)
    |> exclude(:order_by)
    |> Repo.aggregate(:count)
  end

  @doc """
  Given a list of message ids builds a conversation list with most recent conversations
  at the beginning of the list
  """
  @spec list_conversations(map(), boolean) :: [Conversation.t()] | integer
  def list_conversations(args, count \\ false) do
    args
    |> Enum.reduce(
      Message,
      fn
        {:ids, ids}, query ->
          query
          |> where([m], m.id in ^ids)
          |> order_by([m], desc: m.inserted_at)

        {:filter, filter}, query ->
          query |> conversations_with(filter)

        _, query ->
          query
      end
    )
    |> do_list_conversations(args, count)
  end

  # given all the messages related to multiple contacts, group them
  # by contact id into conversation objects
  @spec make_conversations([Message.t()]) :: [Conversation.t()]
  defp make_conversations(messages) do
    # now format the results,
    {contact_messages, _processed_contacts, contact_order} =
      Enum.reduce(
        messages,
        {%{}, %{}, []},
        fn m, {conversations, processed_contacts, contact_order} ->
          conversations = add(m, conversations)

          # We need to do this to maintain the sort order when returning
          # the results. The first time we see a contact, we add them to
          # the contact_order and processed map (using a map for faster lookups)
          if Map.has_key?(processed_contacts, m.contact_id) do
            {conversations, processed_contacts, contact_order}
          else
            {
              conversations,
              Map.put(processed_contacts, m.contact_id, true),
              [m.contact | contact_order]
            }
          end
        end
      )

    # Since we are doing two reduces, we end up with the right order due to the way lists are
    # constructed efficiently (add to front)
    Enum.reduce(
      contact_order,
      [],
      fn contact, acc ->
        [Conversation.new(contact, nil, Enum.reverse(contact_messages[contact])) | acc]
      end
    )
  end

  # for all input contact ids that do not have messages attached to them
  # return a conversation data type with empty messages
  # we don't add empty conversations when we have either include tags or include users set
  @spec add_empty_conversations([Conversation.t()], map()) :: [Conversation.t()]
  defp add_empty_conversations(results, %{filter: %{include_tags: _tags}}),
    do: results

  defp add_empty_conversations(results, %{filter: %{include_labels: _labels}}),
    do: results

  defp add_empty_conversations(results, %{filter: %{include_users: _users}}),
    do: results

  defp add_empty_conversations(results, %{filter: %{id: id}}),
    do: add_empty_conversation(results, [id])

  defp add_empty_conversations(results, %{filter: %{ids: ids}}),
    do: add_empty_conversation(results, ids)

  defp add_empty_conversations(results, _), do: results

  # helper function that actually implements the above functionality
  @spec add_empty_conversation([Conversation.t()], [integer]) :: [Conversation.t()]
  defp add_empty_conversation(results, contact_ids) when is_list(contact_ids) do
    # first find all the contact ids that we have some messages
    present_contact_ids =
      Enum.reduce(
        results,
        [],
        fn r, acc -> [r.contact.id | acc] end
      )

    # the difference is the empty contacts id list
    empty_contact_ids = contact_ids -- present_contact_ids

    # lets load all contacts ids in one query, rather than multiple single queries
    empty_results =
      Contact
      |> where([c], c.id in ^empty_contact_ids)
      |> Repo.all()
      # now only generate conversations objects for the empty contact ids
      |> Enum.reduce(
        [],
        fn contact, acc -> add_conversation(acc, contact) end
      )

    results ++ empty_results
  end

  # add an empty conversation for a specific contact if ONLY if it exists
  @spec add_conversation([Conversation.t()], Contact.t()) :: [Conversation.t()]
  defp add_conversation(results, contact) do
    [Conversation.new(contact, nil, []) | results]
  end

  # restrict the conversations query based on the filters in the input args
  @spec conversations_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp conversations_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:id, id}, query ->
        query |> where([m], m.contact_id == ^id)

      {:ids, ids}, query ->
        query |> where([m], m.contact_id in ^ids)

      {:include_tags, tag_ids}, query ->
        include_tag_filter(query, tag_ids)

      # commenting this out since we search for the labels in full.ex
      # and hence want to include the contacts even if the most recent messages
      # don't fit into the search criteria
      # {:include_labels, label_ids}, query ->
      #   include_label_filter(query, label_ids)

      {:include_users, user_ids}, query ->
        include_user_filter(query, user_ids)

      _filter, query ->
        query
    end)
  end

  # delete code in a few weeks, if re-inserting back, make function private
  # apply filter for message labels
  @doc false
  @spec _include_label_filter(Ecto.Queryable.t(), []) :: Ecto.Queryable.t()
  def _include_label_filter(query, []), do: query

  def _include_label_filter(query, label_ids) do
    flow_labels =
      Glific.Flows.FlowLabel
      |> where([f], f.id in ^label_ids)
      |> select([f], f.name)
      |> Repo.all()

    flow_labels
    |> Enum.reduce(query, fn flow_label, query ->
      where(query, [c], ilike(c.flow_label, ^"%#{flow_label}%"))
    end)
  end

  # apply filter for message tags
  @spec include_tag_filter(Ecto.Queryable.t(), []) :: Ecto.Queryable.t()
  defp include_tag_filter(query, []), do: query

  defp include_tag_filter(query, tag_ids) do
    # given a list of tag_ids, build another list, which includes the tag_ids
    # and also all its parent tag_ids
    all_tag_ids = Tags.include_all_ancestors(tag_ids)

    query
    |> join(:left, [m], mt in MessageTag, as: :mt, on: m.id == mt.message_id)
    |> join(:left, [mt: mt], t in Tag, as: :t, on: t.id == mt.tag_id)
    |> where([mt: mt], mt.tag_id in ^all_tag_ids)
  end

  # apply filter for user ids
  @spec include_user_filter(Ecto.Queryable.t(), []) :: Ecto.Queryable.t()
  defp include_user_filter(query, []), do: query

  defp include_user_filter(query, user_ids) do
    query
    |> where([m], m.user_id in ^user_ids)
  end

  defp add(element, map) do
    Map.update(
      map,
      element.contact,
      [element],
      &[element | &1]
    )
  end

  @doc """
  We need to simulate a few messages as we move to the system. This is a wrapper function
  to add those messages, which trigger specific actions within flows. e.g. include:
  Completed, Failure, Success etc
  """
  @spec create_temp_message(non_neg_integer, any(), Keyword.t()) :: Message.t()
  def create_temp_message(organization_id, body, attrs \\ []) do
    body = String.trim(body || "")

    opts =
      Keyword.merge(
        [
          organization_id: organization_id,
          body: body,
          clean_body: Glific.string_clean(body),
          type: :text
        ],
        attrs
      )

    Message
    |> struct(opts)
  end

  @doc """
  Delete all messages of a contact
  """
  @spec clear_messages(Contact.t()) :: :ok
  def clear_messages(%Contact{} = contact) do
    # get and delete all messages media
    messages_media_ids =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> where([m], m.organization_id == ^contact.organization_id)
      |> select([m], m.media_id)
      |> Repo.all()

    MessageMedia
    |> where([m], m.id in ^messages_media_ids)
    |> Repo.delete_all(timeout: 900_000)

    Message
    |> where([m], m.contact_id == ^contact.id)
    |> where([m], m.organization_id == ^contact.organization_id)
    |> Repo.delete_all()

    reset_contact_fields(contact)

    FlowContext.mark_flows_complete(contact.id, false, source: "clear_messages")

    Communications.publish_data(contact, :cleared_messages, contact.organization_id)

    :ok
  end

  @spec reset_contact_fields(Contact.t()) :: nil
  defp reset_contact_fields(contact) do
    simulator = Contacts.simulator_contact?(contact.phone)

    values = %{
      last_message_number: 0,
      is_org_read: true,
      is_org_replied: true,
      is_contact_replied: true
    }

    values =
      if simulator,
        ## if simulator let's clean all the fields and update reset the session window.
        do:
          values
          |> Map.merge(%{
            fields: %{},
            last_communication_at: DateTime.utc_now(),
            last_message_at: DateTime.utc_now(),
            bsp_status: :session
          }),
        else: values

    Contacts.update_contact(contact, values)

    if simulator,
      do: {:ok, _last_message} = send_default_message(contact)

    nil
  end

  @spec send_default_message(Contact.t(), String.t()) ::
          {:ok, Message.t()} | {:error, atom() | String.t()}
  defp send_default_message(contact, body \\ "Default message body") do
    org = Partners.organization(contact.organization_id)

    attrs = %{
      body: body,
      flow: :outbound,
      media_id: nil,
      organization_id: contact.organization_id,
      receiver_id: contact.id,
      sender_id: org.root_user.id,
      type: :text,
      user_id: org.root_user.id
    }

    create_and_send_message(attrs)
  end

  # cache ttl is 1 hour
  @ttl_limit 1

  @doc false
  @spec validate_media(String.t(), String.t()) :: map()
  def validate_media(url, _type) when url in ["", nil],
    do: %{is_valid: false, message: "Please provide a media URL"}

  def validate_media(url, type) do
    # ensure that this is approximately a url before we send to downstream functions
    if Glific.URI.cast(url) == :ok do
      # We can cache this across all organizations
      # We set a timeout of 60 minutes for this cache entry
      case Caches.get_global({:validate_media, url, type}) do
        {:ok, nil} ->
          do_validate_media(url, type)

        {:ok, value} ->
          value
      end
    else
      %{is_valid: false, message: "This media URL is invalid"}
    end
  end

  @size_limit %{
    "image" => 5120,
    "video" => 16_384,
    "audio" => 16_384,
    "document" => 102_400,
    "sticker" => 100
  }

  @spec do_validate_media(String.t(), String.t()) :: map()
  defp do_validate_media(url, type) do
    # we first decode the string since we have no idea if it was encoded or not
    # if the string was not encoded, decode should not really matter
    # once decoded we encode the string
    url = url |> URI.decode() |> URI.encode()

    case Tesla.get(url, opts: [adapter: [recv_timeout: 10_000]]) do
      {:ok, %Tesla.Env{status: status, headers: headers}} when status in 200..299 ->
        headers
        |> Enum.reduce(%{}, fn header, acc -> Map.put(acc, elem(header, 0), elem(header, 1)) end)
        |> Map.put_new("content-type", "")
        |> Map.put_new("content-length", 0)
        |> do_validate_media(type, url, @size_limit[type])

      _ ->
        %{is_valid: false, message: "This media URL is invalid"}
    end
  end

  @spec do_validate_media(map(), String.t(), String.t(), integer()) :: map()
  defp do_validate_media(headers, type, url, size_limit) do
    cond do
      !do_validate_headers(headers, type, url) ->
        %{is_valid: false, message: "Media content-type is not valid"}

      !do_validate_size(size_limit, headers["content-length"]) ->
        %{
          is_valid: false,
          message: "Size is too big for the #{type}. Maximum size limit is #{size_limit}KB"
        }

      true ->
        value = %{is_valid: true, message: "success"}
        Caches.put_global({:validate_media, url, type}, value, @ttl_limit)
        value
    end
  end

  @spec do_validate_headers(map(), String.t(), String.t()) :: boolean
  defp do_validate_headers(headers, "document", _url),
    do: String.contains?(headers["content-type"], ["pdf", "docx", "xlxs"])

  ## sometimes webp files does not return any content type. We need to figure out another way to validate this
  defp do_validate_headers(headers, "sticker", url),
    do:
      String.contains?(url, [".webp"]) && String.contains?(headers["content-type"], ["image", ""])

  # accept audio file excluding ogg
  defp do_validate_headers(headers, type, _url) when type == "audio" do
    [mime_type, ext] = String.split(headers["content-type"], "/")
    mime_type == "audio" && ext != "ogg"
  end

  defp do_validate_headers(headers, type, _url) when type in ["image", "video"] do
    String.contains?(headers["content-type"], type)
  end

  defp do_validate_headers(_, _, _), do: false

  @spec do_validate_size(Integer, String.t() | integer()) :: boolean
  defp do_validate_size(_size_limit, nil), do: false

  defp do_validate_size(size_limit, content_length) do
    {:ok, content_length} = Glific.parse_maybe_integer(content_length)
    content_length_in_kb = content_length / 1024
    size_limit >= content_length_in_kb
  end

  @doc """
    Get Media type from a url. We will primary use it for when we receive the url from EEX call.
  """
  @spec get_media_type_from_url(String.t(), Keyword.t()) :: tuple()
  def get_media_type_from_url(url, opts \\ []) do
    log_error = Keyword.get(opts, :log_error, true)

    extension =
      url
      |> Path.extname()
      |> String.downcase()
      |> String.replace(".", "")

    ## mime type
    ## We need to figure out a better way to get the mime type. May be MIME::type(url)
    mime_types = [
      {:image, ["png", "jpg", "jpeg"]},
      {:video, ["mp4", "3gp", "3gpp"]},
      {:audio, ["mp3", "wav", "acc", "ogg"]},
      {:document, ["pdf", "docx", "xlsx"]},
      {:sticker, ["webp"]}
    ]

    Enum.find(mime_types, fn {_type, extension_list} -> extension in extension_list end)
    |> case do
      {type, _} ->
        {type, url}

      _ ->
        if log_error, do: Logger.info("Could not find media type for extension: #{extension}")
        {:text, nil}
    end
  end

  @doc """
  Mark that the user has read all messages sent by a given contact
  """
  @spec mark_contact_messages_as_read(non_neg_integer, non_neg_integer) :: nil
  def mark_contact_messages_as_read(contact_id, _organization_id) do
    Contact
    |> where([c], c.id == ^contact_id)
    |> Repo.update_all(set: [is_org_read: true])
  end
end
