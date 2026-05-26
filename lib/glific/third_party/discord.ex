defmodule Glific.ThirdParty.Discord do
  @moduledoc """
  Sends notifications to a Discord channel via an incoming webhook URL.
  """

  import Glific.SafeLog

  @doc """
  Posts a plain-text message to the configured Discord webhook channel.
  """
  @spec post_message(String.t()) :: :ok | {:error, String.t()}
  def post_message(content) do
    webhook_url = Application.get_env(:glific, :discord_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Glific.log_error("Discord webhook URL not configured; skipping Discord notification", false)
      :ok
    else
      body = Jason.encode!(%{content: content})

      case Tesla.post(webhook_url, body, headers: [{"content-type", "application/json"}]) do
        {:ok, %Tesla.Env{status: status}} when status in 200..204 ->
          :ok

        {:ok, %Tesla.Env{status: status, body: resp_body}} ->
          Glific.log_error("Discord webhook failed: status=#{status}, body=#{safe_inspect(resp_body)}")
          {:error, "Discord webhook returned #{status}"}

        {:error, reason} ->
          Glific.log_error("Discord webhook request error: #{safe_inspect(reason)}")
          {:error, "Discord webhook request failed"}
      end
    end
  end
end
