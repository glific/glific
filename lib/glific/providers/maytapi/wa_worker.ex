defmodule Glific.Providers.Maytapi.WaWorker do
  @moduledoc """
  A worker to handle send message in whatsapp group processes
  """
  import Ecto.Query, warn: false

  use Oban.Worker,
    queue: :wa_group,
    max_attempts: 2,
    priority: 0

  alias Glific.{
    Messages.Message,
    Providers.Maytapi.ApiClient,
    Partners,
    Partners.Organization,
    Providers.Worker,
    WAGroup.WAManagedPhone,
    Repo,
    Providers.Gupshup.ResponseHandler
  }

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message}} = job) do
    organization = Partners.organization(message["organization_id"])

    if is_nil(organization.services["bsp"]) do
      Worker.handle_credential_error(message)
    else
      perform(job, organization)
    end
  end

  @spec perform(Oban.Job.t(), Organization.t()) ::
          :ok | {:error, String.t()} | {:snooze, pos_integer()}
  defp perform(
         %Oban.Job{args: %{"payload" => payload}},
         organization
       ) do
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactoring because of credo warning
    case ExRated.check_rate(
           organization.shortcode,
           # the bsp limit is per organization per shortcode
           1000,
           organization.services["bsp"].keys["bsp_limit"]
         ) do
      {:ok, _} ->
        phone_id = payload["phone_id"]
        process_maytapi(organization.id, payload, phone_id)

      _ ->
        Worker.default_send_rate_handler()
    end
  end

  @spec process_maytapi(non_neg_integer(), map(), non_neg_integer()) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp process_maytapi(org_id, payload, phone_id) do
    case ApiClient.send_message(org_id, payload, phone_id) do
      {:ok, response} -> {:ok, response}
      _ -> {:error, "error while sending message"}
    end
  end
end
