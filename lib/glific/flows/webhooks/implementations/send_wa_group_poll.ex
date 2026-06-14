defmodule Glific.Flows.Webhooks.SendWaGroupPoll do
  @moduledoc """
  Send a WhatsApp group poll via the Maytapi provider.

  Accepts a `wa_group` map (must contain `id` and `wa_managed_phone_id`),
  a `poll_uuid` string (must be a valid UUID), and uses the `organization_id`
  from the dispatcher context to look up the managed phone, WA group, and poll
  records, then delegates to `Maytapi.Message.create_and_send_wa_message/3`.

  Returns `{:ok, %{poll: poll_content}}` on success, or `{:error, String.t()}`
  on any validation or database-lookup failure.

  Migrated from `Glific.Clients.CommonWebhook.webhook("send_wa_group_poll", ...)`.
  """

  use Glific.Flows.Webhooks.Sync, name: "send_wa_group_poll"

  alias Glific.Groups.WAGroup
  alias Glific.Providers.Maytapi
  alias Glific.Repo
  alias Glific.SafeLog
  alias Glific.WAGroup.WAManagedPhone
  alias Glific.WAGroup.WaPoll

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, String.t()}
  def call(fields, ctx) do
    org_id = ctx.organization_id

    with {:ok, parsed} <- parse_wa_poll_params(fields),
         {:ok, wa_phone} <-
           Repo.fetch_by(WAManagedPhone, %{
             id: parsed.wa_group["wa_managed_phone_id"],
             organization_id: org_id
           }),
         {:ok, wa_group} <-
           Repo.fetch_by(WAGroup, %{
             id: parsed.wa_group["id"],
             organization_id: org_id
           }),
         {:ok, wa_poll} <-
           Repo.fetch_by(WaPoll, %{
             uuid: parsed.poll_uuid,
             organization_id: org_id
           }),
         {:ok, wa_message} <-
           Maytapi.Message.create_and_send_wa_message(wa_phone, wa_group, %{
             poll_id: wa_poll.id
           }) do
      {:ok, %{poll: wa_message.poll_content}}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, SafeLog.safe_inspect(reason)}
    end
  end

  @spec parse_wa_poll_params(map()) :: {:ok, map()} | {:error, String.t()}
  defp parse_wa_poll_params(fields) do
    with {true, _} <- {is_map(fields["wa_group"]), :wa_group},
         {:ok, _} <- Ecto.UUID.cast(fields["poll_uuid"]) do
      {:ok,
       %{
         wa_group: fields["wa_group"],
         poll_uuid: fields["poll_uuid"]
       }}
    else
      :error ->
        {:error, "poll_uuid is invalid"}

      {false, field} ->
        {:error, "#{field} is invalid"}
    end
  end
end
