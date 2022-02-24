defmodule Glific.Providers.Gupshup.Worker do
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
    Providers.Gupshup.ApiClient,
    Providers.Gupshup.ResponseHandler,
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
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactoring because of credo warning
    case ExRated.check_rate(
           organization.shortcode,
           # the bsp limit is per organization per shortcode
           1000,
           organization.services["bsp"].keys["bsp_limit"]
         ) do
      {:ok, _} ->
        if Contacts.is_simulator_contact?(payload["destination"]) do
          Worker.process_simulator(message)
        else
          process_gupshup(organization.id, payload, message, attrs)
        end

      _ ->
        Worker.default_send_rate_handler()
    end
  end

  @spec process_gupshup(
          non_neg_integer(),
          map(),
          Message.t(),
          map()
        ) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp process_gupshup(
         org_id,
         payload,
         message,
         %{
           "is_hsm" => true,
           "params" => params,
           "template_uuid" => template_uuid,
           "template_type" => template_type
         } = _attrs
       ) do
    template_payload =
      %{
        "source" => payload["source"],
        "destination" => payload["destination"],
        "template" => Jason.encode!(%{"id" => template_uuid, "params" => params}),
        "src.name" => payload["src.name"]
      }
      |> check_media_template(payload, template_type)

    ApiClient.send_template(
      org_id,
      template_payload
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

  @spec check_media_template(map(), map(), String.t()) :: map()
  defp check_media_template(template_payload, payload, template_type)
       when template_type in ["image", "video", "document"] do
    template_payload
    |> Map.merge(%{
      "message" =>
        Jason.encode!(%{
          "type" => template_type,
          template_type => %{"link" => parse_media_url(payload, template_type)}
        })
    })
  end

  defp check_media_template(template_payload, _payload, _template_type), do: template_payload

  @spec parse_media_url(map(), String.t()) :: String.t()
  defp parse_media_url(template_payload, template_type) when template_type in ["image"],
    do: Jason.decode!(template_payload["message"])["originalUrl"]

  defp parse_media_url(template_payload, template_type)
       when template_type in ["video", "document"],
       do: Jason.decode!(template_payload["message"])["url"]
end
