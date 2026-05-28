defmodule Glific.ThirdParty.Discord do
  @moduledoc """
  Sends notifications to a Discord channel via an incoming webhook URL.
  """

  require Logger

  import Glific.SafeLog

  @timeout_ms 5_000

  @doc """
  Posts a rich embed to the configured Discord webhook channel.

  The `embed` map follows the Discord embed object structure:
  https://discord.com/developers/docs/resources/message#embed-object

  ## Example

      Discord.post_embed(%{
        title: "Alert",
        description: "Something happened",
        color: 0x5865F2,
        fields: [%{name: "Org", value: "Acme", inline: true}]
      })

  """
  @spec post_embed(map()) :: :ok | {:error, String.t()}
  def post_embed(embed) when is_map(embed) do
    do_post(%{embeds: [embed]})
  end

  def post_embed(_), do: {:error, "Discord embed must be a map"}

  @spec do_post(map()) :: :ok | {:error, String.t()}
  defp do_post(payload) do
    webhook_url = Application.get_env(:glific, :discord_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.warning("Discord webhook URL not configured; skipping Discord notification")
      :ok
    else
      with {:ok, body} <- encode(payload),
           {:ok, response} <- send_request(webhook_url, body) do
        handle_response(response)
      end
    end
  end

  @spec encode(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp encode(payload) do
    case Jason.encode(payload) do
      {:ok, body} ->
        {:ok, body}

      {:error, reason} ->
        Glific.log_error("Discord payload encoding failed: #{safe_inspect(reason)}")
        {:error, "Discord payload encoding failed"}
    end
  end

  @spec send_request(String.t(), String.t()) :: {:ok, Tesla.Env.t()} | {:error, String.t()}
  defp send_request(webhook_url, body) do
    case Tesla.post(webhook_url, body,
           headers: [{"content-type", "application/json"}],
           opts: [adapter: [recv_timeout: @timeout_ms]]
         ) do
      {:ok, env} ->
        {:ok, env}

      {:error, reason} ->
        Glific.log_error("Discord webhook request error: #{safe_inspect(reason)}")
        {:error, "Discord webhook request failed"}
    end
  end

  @spec handle_response(Tesla.Env.t()) :: :ok | {:error, String.t()}
  defp handle_response(%Tesla.Env{status: status}) when status in 200..204, do: :ok

  defp handle_response(%Tesla.Env{status: 429, headers: headers}) do
    retry_after = headers |> List.keyfind("retry-after", 0, {nil, "unknown"}) |> elem(1)
    Glific.log_error("Discord webhook rate limited; retry after #{retry_after}s")
    {:error, "Discord webhook rate limited"}
  end

  defp handle_response(%Tesla.Env{status: status, body: body}) do
    Glific.log_error("Discord webhook failed: status=#{status}, body=#{safe_inspect(body)}")
    {:error, "Discord webhook returned #{status}"}
  end
end
