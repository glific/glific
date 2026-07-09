defmodule Glific.Flows.Webhooks.ParseViaGptVision do
  @moduledoc """
  Parse an image via OpenAI GPT Vision (`parse_via_gpt_vision` flow-webhook node).

  Migrated from `Glific.Clients.CommonWebhook.webhook("parse_via_gpt_vision", ...)` onto the
  central `Glific.Flows.Webhooks` framework; behaviour is preserved one-for-one. Failure
  reporting and latency telemetry are added by `Glific.Flows.Webhooks.Dispatcher`, not here.

  Failures return a bare string (not `%{success: false}`) so the flow routes to the "Failure"
  category (`Glific.Flows.Webhook` keys off `is_map`).
  """

  use Glific.Flows.Webhooks.Sync, name: "parse_via_gpt_vision"

  alias Glific.OpenAI.ChatGPT
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) :: map() | String.t()
  def call(fields, _ctx) do
    url = fields["url"]
    org_id = parse_org_id(fields)

    # validating if the url passed is a valid image url
    with %{is_valid: true} <- Glific.Messages.validate_media(url, "image"),
         {:ok, fields} <- inline_image(fields, url, org_id),
         {:ok, fields} <- ChatGPT.parse_response_format(fields),
         {:ok, response} <- ChatGPT.gpt_vision(fields) do
      %{success: true, response: ChatGPT.parse_gpt_response(response)}
    else
      %{is_valid: false, message: message} ->
        message

      {:error, error} ->
        error
    end
  end

  # Best-effort org_id for the media download. Returns nil if absent/unparseable rather
  # than raising.
  @spec parse_org_id(map()) :: non_neg_integer() | nil
  defp parse_org_id(fields) do
    case Glific.parse_maybe_integer(fields["organization_id"]) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  # Download the image and pass it to OpenAI as an inline base64 data URL rather than a bare
  # link (Gupshup media URLs expire / need auth, so a link OpenAI fetches later can 404).
  @spec inline_image(map(), String.t(), non_neg_integer() | nil) ::
          {:ok, map()} | {:error, String.t()}
  defp inline_image(fields, image_url, org_id) do
    case GupshupClient.download_media_content(image_url, org_id) do
      {:ok, encoded_image, content_type} ->
        # OpenAI needs a data URL (data:<mime>;base64,<...>), not bare base64.
        # Use the server's Content-Type since Gupshup media URLs carry no extension.
        mime = normalize_image_mime(content_type)
        {:ok, Map.put(fields, "url", "data:#{mime};base64,#{encoded_image}")}

      {:error, _reason} ->
        {:error, "Failed to download image for vision parsing"}
    end
  end

  @spec normalize_image_mime(String.t() | nil) :: String.t()
  defp normalize_image_mime(nil), do: "image/jpeg"

  defp normalize_image_mime(content_type),
    do: content_type |> String.split(";") |> hd() |> String.trim()
end
