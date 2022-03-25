defmodule Glific.Providers.Gupshup.Enterprise.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :gupshup,
    max_attempts: 2,
    priority: 0

  alias Glific.{
    Contacts,
    Messages.Message,
    Partners,
    Partners.Organization,
    Providers.Gupshup.Enterprise.ApiClient,
    Providers.Gupshup.Enterprise.ResponseHandler,
    Providers.Worker
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
         %Oban.Job{args: %{"message" => message, "payload" => payload, "attrs" => attrs}},
         organization
       ) do
    case ExRated.check_rate(
           organization.shortcode,
           # the bsp limit is per organization per shortcode
           1000,
           organization.services["bsp"].keys["bsp_limit"]
         ) do
      {:ok, _} ->
        if Contacts.is_simulator_contact?(payload["send_to"]) do
          Worker.process_simulator(message)
        else
          process_gupshup(organization.id, payload, message, attrs)
        end

      _ ->
        Worker.default_send_rate_handler()
    end
  end

  @spec process_gupshup(non_neg_integer(), map(), Message.t(), map()) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp process_gupshup(org_id, payload, %{"is_hsm" => true, "body" => body} = message, attrs) do
    ApiClient.send_template(org_id, %{
      "msg" => body,
      "send_to" => payload["send_to"],
      "has_buttons" => attrs["has_buttons"]
    })
    |> ResponseHandler.handle_response(message)
  end

  defp process_gupshup(
         org_id,
         payload,
         %{"interactive_template_id" => _interactive_template_id} = message,
         _attrs
       ) do
    ApiClient.send_interactive_template(
      org_id,
      payload
    )
    |> ResponseHandler.handle_response(message)
  end

  defp process_gupshup(org_id, payload, message, _attrs) do
    ApiClient.send_message(
      org_id,
      payload
    )
    |> ResponseHandler.handle_response(message)
  end
end
