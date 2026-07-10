defmodule Glific.Flows.Webhooks.SendWaGroupPoll do
  @moduledoc """
  Send a WhatsApp group poll in a flow (`send_wa_group_poll` flow-webhook node).

  Migrated from `Glific.Clients.CommonWebhook.webhook("send_wa_group_poll", ...)` onto the
  central `Glific.Flows.Webhooks` framework; behaviour is preserved one-for-one. Failure
  reporting and latency telemetry are added by `Glific.Flows.Webhooks.Dispatcher`, not here.
  """

  use Glific.Flows.Webhooks.Sync, name: "send_wa_group_poll"

  alias Glific.{
    Flows.Webhooks.ErrorType,
    Groups.WAGroup,
    Providers.Maytapi,
    Repo,
    SafeLog,
    WAGroup.WAManagedPhone,
    WAGroup.WaPoll
  }

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def call(fields, _ctx) do
    with {:ok, fields} <- parse_wa_poll_params(fields),
         {:ok, wa_phone} <-
           Repo.fetch_by(WAManagedPhone, %{
             id: fields.wa_group["wa_managed_phone_id"],
             organization_id: fields.organization_id
           }),
         {:ok, wa_group} <-
           Repo.fetch_by(WAGroup, %{
             id: fields.wa_group["id"],
             organization_id: fields.organization_id
           }),
         {:ok, wa_poll} <-
           Repo.fetch_by(WaPoll, %{
             uuid: fields.poll_uuid,
             organization_id: fields.organization_id
           }),
         {:ok, wa_message} <-
           Maytapi.Message.create_and_send_wa_message(wa_phone, wa_group, %{poll_id: wa_poll.id}) do
      {:ok, %{success: true, poll: wa_message.poll_content}}
    else
      {:error, error_type, message} when is_atom(error_type) ->
        {:error, error_type, message}

      {:error, reason} when is_binary(reason) ->
        {:error, :unknown, reason}

      {:error, reason} ->
        {:error, :unknown, SafeLog.safe_inspect(reason)}
    end
  end

  @spec parse_wa_poll_params(map()) :: {:ok, map()} | {:error, ErrorType.t(), String.t()}
  defp parse_wa_poll_params(fields) do
    # if wa_group is in the map, then the inner keys will be already filled by
    # webhook module
    with {true, _} <- {is_map(fields["wa_group"]), :wa_group},
         {true, _} <- {is_integer(fields["organization_id"]), :organization_id},
         {:ok, _} <-
           Ecto.UUID.cast(fields["poll_uuid"]) do
      {:ok,
       %{
         wa_group: fields["wa_group"],
         poll_uuid: fields["poll_uuid"],
         organization_id: fields["organization_id"]
       }}
    else
      :error ->
        {:error, :invalid_input, "poll_uuid is invalid"}

      {false, field} ->
        {:error, :invalid_input, "#{field} is invalid"}
    end
  end
end
