defmodule Glific.ThirdParty.Discord do
  @moduledoc """
  Sends notifications to a Discord channel via an incoming webhook URL.
  """

  require Logger

  @doc """
  Posts a plain-text message to the configured Discord webhook channel.
  """
  @spec post_message(String.t()) :: :ok | {:error, String.t()}
  def post_message(content) do
    webhook_url = Application.get_env(:glific, :discord_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.warning("Discord webhook URL not configured; skipping Discord notification")
      :ok
    else
      body = Jason.encode!(%{content: content})

      case Tesla.post(webhook_url, body, headers: [{"content-type", "application/json"}]) do
        {:ok, %Tesla.Env{status: status}} when status in 200..204 ->
          :ok

        {:ok, %Tesla.Env{status: status, body: resp_body}} ->
          Logger.error("Discord webhook failed: status=#{status}, body=#{inspect(resp_body)}")
          {:error, "Discord webhook returned #{status}"}

        {:error, reason} ->
          Logger.error("Discord webhook request error: #{inspect(reason)}")
          {:error, "Discord webhook request failed"}
      end
    end
  end
end
