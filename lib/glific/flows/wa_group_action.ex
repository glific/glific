defmodule Glific.Flows.WAGroupAction do
  @moduledoc false

  # TODO: doc needed

  alias Glific.Flows
  alias Glific.Providers.Maytapi.Message
  alias Glific.Flows.ContactAction
  alias Glific.Flows.MessageVarParser
  alias Glific.Flows.Localization
  alias Glific.WAGroup.WAMessage
  alias Glific.Flows.Action
  alias Glific.Flows.FlowContext
  alias Glific.Repo

  # TODO: docs
  @spec send_message(FlowContext.t(), Action.t(), [WAMessage.t()], non_neg_integer | nil) ::
          {:ok, map(), any()}
  def send_message(context, action, messages, cid \\ nil)

  def send_message(context, action, messages, _cid) do
    {context, action} = process_labels(context, action)

    message_vars = FlowContext.get_vars_to_parse(context)

    text = Localization.get_translation(context, action, :text)

    body =
      text
      |> MessageVarParser.parse(message_vars)

    do_send_message(context, action, messages, %{
      body: body,
      text: text,
      flow_label: action.labels
    })
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

    attachments = Localization.get_translation(context, action, :attachments)

    {type, media_id} = ContactAction.get_media_from_attachment(attachments, text, context, nil)

    context = Repo.preload(context, [:wa_group, wa_group: :wa_managed_phone])

    attrs = %{
      uuid: action.node_uuid,
      body: body,
      type: type,
      media_id: media_id,
      contact_id: context.wa_group.wa_managed_phone.contact_id,
      organization_id: organization_id,
      flow_label: flow_label,
      flow_id: context.flow_id,
      send_at: DateTime.add(DateTime.utc_now(), max(context.delay, action.delay)),
      is_optin_flow: Flows.optin_flow?(context.flow),
      message: body
    }

    attrs
    |> then(
      &Message.create_and_send_wa_message(context.wa_group.wa_managed_phone, context.wa_group, &1)
    )
    |> handle_message_result(context, messages, attrs)
  end

  # TODO: Need to do more here...
  defp handle_message_result(result, context, messages, attrs) do
    {:ok, context}
    # dbg()
    # case result do
    #   {:ok, message} ->
    #     context = FlowContext.update_recent(context, message, :recent_outbound)
    #     {:ok, %{context | delay: context.delay + @min_delay}, messages}

    #   # {:error, error} ->
    #   #   error(context, error, attrs)
    # end
  end
end
