defmodule Glific.Flows.WAGroupAction do
  @moduledoc false

  # TODO: doc needed

  alias Glific.Flows
  alias Glific.WAManagedPhones
  alias Glific.WAGroup.WAManagedPhone
  alias Glific.Groups.WAGroups
  alias Glific.Providers.Maytapi.Message
  alias Glific.Flows.ContactAction
  alias Glific.Flows.MessageVarParser
  alias Glific.Flows.Localization
  alias Glific.WAGroup.WAMessage
  alias Glific.Flows.Action
  alias Glific.Flows.FlowContext

  @spec send_message(FlowContext.t(), Action.t(), [WAMessage.t()], non_neg_integer | nil) ::
          {:ok, map(), any()}
  def send_message(context, action, messages, cid \\ nil)

  def send_message(context, action, messages, cid) do
    {context, action} = process_labels(context, action)

    # TODO: do we need same thing for group?
    # {cid, message_vars} = resolve_cid(context, cid)

    message_vars = FlowContext.get_vars_to_parse(context)
    # # get the text translation if needed
    text = Localization.get_translation(context, action, :text)

    body =
      text
      |> MessageVarParser.parse(message_vars)

    with {false, context} <- ContactAction.has_loops?(context, body, messages) do
      do_send_message(context, action, messages, %{
        body: body,
        text: text,
        flow_label: action.labels
      })
    end
  end

  @spec process_labels(FlowContext.t(), Action.t()) :: {FlowContext.t(), Action.t()}
  defp process_labels(context, %{labels: nil} = action), do: {context, action}

  defp process_labels(context, %{labels: labels} = action) do
    flow_label =
      labels
      |> Enum.map_join(", ", fn label ->
        FlowContext.parse_context_string(context, label["name"])
      end)

    {context, Map.put(action, :labels, flow_label)}
  end

  @spec do_send_message(FlowContext.t(), Action.t(), [Message.t()], map()) ::
          {:ok, map(), any()}
  defp do_send_message(
         context,
         action,
         messages,
         %{
           body: body,
           text: text,
           flow_label: flow_label
         }
       ) do
    organization_id = context.organization_id

    _attachments = Localization.get_translation(context, action, :attachments)

    # TODO: handle media and type

    # {type, media_id} = get_media_from_attachment(attachments, text, context, cid)

    wa_group = WAGroups.get_wa_group!(context.wa_group_id)
    wa_phone = WAManagedPhones.get_wa_managed_phone!(wa_group.wa_managed_phone_id)
    # TODO: add contact_id
    attrs = %{
      uuid: action.node_uuid,
      body: body,
      type: "IMAGE",
      media_id: nil,
      # contact_id: cid,
      organization_id: organization_id,
      flow_label: flow_label,
      flow_id: context.flow_id,
      send_at: DateTime.add(DateTime.utc_now(), max(context.delay, action.delay)),
      is_optin_flow: Flows.optin_flow?(context.flow)
    }

    attrs
    |> then(&Message.create_and_send_wa_message(wa_phone, wa_group, &1))
    |> handle_message_result(context, messages, attrs)
  end

  # TODO: Need to do more here...
  defp handle_message_result(_result, context, _message, _attrs) do
    {:ok, context}
  end
end
