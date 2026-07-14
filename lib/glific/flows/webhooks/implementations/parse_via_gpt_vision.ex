defmodule Glific.Flows.Webhooks.ParseViaGptVision do
  @moduledoc """
  Parse an image via OpenAI GPT Vision (`parse_via_gpt_vision` node).
  """

  use Glific.Flows.Webhooks.Sync, name: "parse_via_gpt_vision"

  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.OpenAI.ChatGPT
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def call(fields, _ctx) do
    url = fields["url"]
    org_id = parse_org_id(fields)

    with %{is_valid: true} <- Glific.Messages.validate_media(url, "image"),
         {:ok, fields} <- inline_image(fields, url, org_id),
         {:ok, fields} <- ChatGPT.parse_response_format(fields),
         {:ok, response} <- ChatGPT.gpt_vision(fields) do
      {:ok, %{success: true, response: ChatGPT.parse_gpt_response(response)}}
    else
      %{is_valid: false, message: message} ->
        {:error, :invalid_media_url, message}

      {:error, message} ->
        {:error, :unknown, message}
    end
  end

  @spec parse_org_id(map()) :: non_neg_integer() | nil
  defp parse_org_id(fields) do
    case Glific.parse_maybe_integer(fields["organization_id"]) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  # Inline the image as a base64 data URL: Gupshup media URLs expire / need auth, so a bare link
  # OpenAI fetches later can 404. Content-Type gives the mime (URLs carry no extension).
  @spec inline_image(map(), String.t(), non_neg_integer() | nil) ::
          {:ok, map()} | {:error, String.t()}
  defp inline_image(fields, image_url, org_id) do
    case GupshupClient.download_media_content(image_url, org_id) do
      {:ok, encoded_image, content_type} ->
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
