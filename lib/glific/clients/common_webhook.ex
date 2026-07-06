defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.Certificates.Certificate
  alias Glific.Certificates.CertificateTemplate
  alias Glific.Flows.Webhook
  alias Glific.Flows.Webhook.SystemError
  alias Glific.Flows.Webhooks.Dispatcher
  alias Glific.Flows.Webhooks.Instrumentation
  alias Glific.Groups.WAGroup
  alias Glific.OpenAI.ChatGPT
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient
  alias Glific.Providers.Maytapi
  alias Glific.Repo
  alias Glific.SafeLog
  alias Glific.ThirdParty.GoogleSlide.Slide
  alias Glific.WAGroup.WAManagedPhone
  alias Glific.WAGroup.WaPoll

  require Logger

  @doc """
  Create a webhook with different signatures along with header, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map(), list()) :: map() | String.t()
  def webhook(function, fields, _headers), do: webhook(function, fields)

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("parse_via_chat_gpt", fields) do
    org_id = parse_org_id(fields)

    with_failure_reporting("parse_via_chat_gpt", webhook_meta(org_id, fields), fn ->
      with {:ok, fields} <- parse_chatgpt_fields(fields),
           {:ok, fields} <- parse_response_format(fields),
           {:ok, text} <- Glific.get_open_ai_key() |> ChatGPT.parse(fields) do
        %{
          success: true,
          parsed_msg: parse_gpt_response(text)
        }
      else
        {:error, error} ->
          error
      end
    end)
  end

  @spec webhook(String.t(), map()) :: any()
  def webhook("parse_via_gpt_vision", fields) do
    url = fields["url"]
    org_id = parse_org_id(fields)

    # Failures return a bare string (not %{success: false}) so the flow routes
    # to the "Failure" category (lib/glific/flows/webhook.ex keys off is_map).
    with_failure_reporting("parse_via_gpt_vision", webhook_meta(org_id, fields), fn ->
      # validating if the url passed is a valid image url
      with %{is_valid: true} <- Glific.Messages.validate_media(url, "image"),
           {:ok, fields} <- maybe_inline_image(fields, url, org_id),
           {:ok, fields} <- parse_response_format(fields),
           {:ok, response} <- ChatGPT.gpt_vision(fields) do
        %{success: true, response: parse_gpt_response(response)}
      else
        %{is_valid: false, message: message} ->
          message

        {:error, error} ->
          error
      end
    end)
  end

  def webhook("get_buttons", fields) do
    buttons =
      fields["buttons_data"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields),
    do: %{response: String.equivalent?(fields["correct_response"], fields["user_response"])}

  # Migrated to Glific.Flows.Webhooks.Geolocation. This clause now routes
  # through the centralised dispatcher, which wraps the call with failure
  # reporting + latency telemetry.
  def webhook("geolocation", fields),
    do: Dispatcher.dispatch("geolocation", fields)

  # webhook for sending whatsapp group polls in a flow
  def webhook("send_wa_group_poll", fields) do
    org_id = parse_org_id(fields)

    with_failure_reporting("send_wa_group_poll", webhook_meta(org_id, fields), fn ->
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
        %{success: true, poll: wa_message.poll_content}
      else
        {:error, reason} when is_binary(reason) ->
          reason

        {:error, reason} ->
          SafeLog.safe_inspect(reason)
      end
    end)
  end

  def webhook("create_certificate", fields) do
    org_id = parse_org_id(fields)

    with_failure_reporting("create_certificate", webhook_meta(org_id, fields), fn ->
      with {:ok, parsed_fields} <- parse_certificate_params(fields),
           {:ok, certificate_template} <- fetch_certificate_template(parsed_fields),
           {:ok, slide_details} <-
             Slide.parse_slides_url(certificate_template.url) do
        Certificate.generate_certificate(
          parsed_fields,
          parsed_fields.contact["id"],
          slide_details.presentation_id,
          slide_details.page_id
        )
      else
        {:error, reason} ->
          reason
      end
    end)
  end

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}

  defp parse_response_format(%{"response_format" => response_format} = fields) do
    case response_format do
      %{"type" => "json_schema"} ->
        # Support for json_schema is only since gpt-4o-2024-08-06
        {:ok, Map.put(fields, "model", "gpt-4o-2024-08-06")}

      %{"type" => "json_object"} ->
        {:ok, fields}

      nil ->
        {:ok, fields}

      _ ->
        {:error, "response_format type should be json_schema or json_object"}
    end
  end

  defp parse_response_format(fields), do: {:ok, Map.put(fields, "response_format", nil)}

  @spec parse_gpt_response(String.t()) :: any()
  defp parse_gpt_response(response) do
    case Jason.decode(response) do
      {:ok, decoded_response} ->
        decoded_response

      {:error, _err} ->
        response
    end
  end

  @spec parse_chatgpt_fields(map()) :: {:ok, map()} | {:error, String.t()}
  defp parse_chatgpt_fields(fields) do
    if fields["question_text"] in [nil, ""] do
      {:error, "question_text is empty"}
    else
      {:ok,
       %{
         "question_text" => Map.get(fields, "question_text"),
         "prompt" => Map.get(fields, "prompt", nil),
         # ID of the model to use.
         "model" => Map.get(fields, "model", "gpt-4o"),
         # The sampling temperature, between 0 and 1.
         # Higher values like 0.8 will make the output more random,
         # while lower values like 0.2 will make it more focused and deterministic.
         "temperature" => Map.get(fields, "temperature", 0),
         "response_format" => Map.get(fields, "response_format", nil)
       }}
    end
  end

  @spec parse_wa_poll_params(map()) :: {:ok, map()} | {:error, String.t()}
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
        {:error, "poll_uuid is invalid"}

      {false, field} ->
        {:error, "#{field} is invalid"}
    end
  end

  @spec parse_certificate_params(map()) :: {:ok, map()} | {:error, String.t()}
  defp parse_certificate_params(fields) do
    certificate_params_schema = %{
      certificate_id: [
        type: :integer,
        required: true,
        cast_func: fn value ->
          {:ok, if(is_binary(value), do: Glific.parse_maybe_integer!(value), else: value)}
        end
      ],
      contact: [type: :map, required: true],
      replace_texts: [type: :map, required: true],
      organization_id: [type: :integer, required: true]
    }

    Tarams.cast(fields, certificate_params_schema) |> Glific.handle_tarams_result()
  end

  @spec fetch_certificate_template(map()) :: {:ok, CertificateTemplate.t()} | {:error, String.t()}
  defp fetch_certificate_template(fields) do
    case Repo.fetch_by(CertificateTemplate, %{
           id: fields.certificate_id,
           organization_id: fields.organization_id
         }) do
      {:ok, certificate_template} ->
        {:ok, certificate_template}

      {:error, _reason} ->
        Logger.error(
          "Certificate template not found for ID: #{fields.certificate_id} and organization: #{fields.organization_id}"
        )

        {:error, "Certificate template not found for ID: #{fields.certificate_id}"}
    end
  end

  # Best-effort org_id for failure reporting tags. Returns nil if absent/unparseable
  # rather than raising, since it's only used for the AppSignal tag.
  @spec parse_org_id(map()) :: non_neg_integer() | nil
  defp parse_org_id(fields) do
    case Glific.parse_maybe_integer(fields["organization_id"]) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  @spec maybe_inline_image(map(), String.t(), non_neg_integer() | nil) ::
          {:ok, map()} | {:error, String.t()}
  defp maybe_inline_image(fields, image_url, org_id) do
    if FunWithFlags.enabled?(:is_gpt_vision_base64_enabled, for: %{organization_id: org_id}) do
      case GupshupClient.download_media_content(image_url, org_id) do
        {:ok, encoded_image, content_type} ->
          # OpenAI needs a data URL (data:<mime>;base64,<...>), not bare base64.
          # Use the server's Content-Type since Gupshup media URLs carry no extension.
          mime = normalize_image_mime(content_type)
          {:ok, Map.put(fields, "url", "data:#{mime};base64,#{encoded_image}")}

        {:error, _reason} ->
          {:error, "Failed to download image for vision parsing"}
      end
    else
      {:ok, fields}
    end
  end

  @spec normalize_image_mime(String.t() | nil) :: String.t()
  defp normalize_image_mime(nil), do: "image/jpeg"

  defp normalize_image_mime(content_type),
    do: content_type |> String.split(";") |> hd() |> String.trim()

  @spec with_failure_reporting(String.t(), map(), (-> any())) :: any()
  defp with_failure_reporting(webhook_name, meta, fun) do
    start = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      duration_ms = System.monotonic_time(:millisecond) - start
      record_webhook_outcome(result, webhook_name, meta, duration_ms)
      result
    rescue
      exception ->
        duration_ms = System.monotonic_time(:millisecond) - start
        report_webhook_failure(webhook_name, meta, nil, Exception.message(exception))
        record_webhook_metrics(webhook_name, "failure", duration_ms)
        reraise exception, __STACKTRACE__
    end
  end

  @spec record_webhook_outcome(any(), String.t(), map(), non_neg_integer()) ::
          :ok
  defp record_webhook_outcome(%{success: false} = result, webhook_name, meta, duration_ms) do
    {status, reason} = extract_status_and_reason(result)
    report_webhook_failure(webhook_name, meta, status, reason)
    record_webhook_metrics(webhook_name, "failure", duration_ms)
  end

  # nil / non-map results route to the flow's Failure category (see
  # Glific.Flows.Webhook.handle/3, which keys off is_map). Treat them as
  # failures here too
  defp record_webhook_outcome(result, webhook_name, meta, duration_ms)
       when is_nil(result) or not is_map(result) do
    reason = if is_binary(result), do: result, else: SafeLog.safe_inspect(result)
    report_webhook_failure(webhook_name, meta, nil, reason)
    record_webhook_metrics(webhook_name, "failure", duration_ms)
  end

  defp record_webhook_outcome(_result, webhook_name, _meta, duration_ms) do
    record_webhook_metrics(webhook_name, "success", duration_ms)
    :ok
  end

  @spec record_webhook_metrics(String.t() | nil, String.t(), non_neg_integer()) :: :ok
  defp record_webhook_metrics(webhook_name, status, duration_ms) do
    Instrumentation.track_webhook_count(webhook_name, status)
    Instrumentation.track_webhook_latency(webhook_name, status, duration_ms)
    :ok
  end

  @spec extract_status_and_reason(map()) :: {integer() | nil, String.t() | nil}
  defp extract_status_and_reason(result) do
    case result do
      %{http_status: status, reason: reason} when is_integer(status) and is_binary(reason) ->
        {status, reason}

      %{http_status: status} when is_integer(status) ->
        {status, nil}

      %{asr_response_text: status} when is_integer(status) ->
        {status, nil}

      %{asr_response_text: status} when is_binary(status) ->
        {nil, status}

      %{reason: status} when is_binary(status) ->
        {nil, status}

      other ->
        {nil, SafeLog.safe_inspect(other)}
    end
  end

  @spec report_webhook_failure(
          String.t(),
          map(),
          integer() | nil,
          String.t() | nil
        ) :: :ok
  defp report_webhook_failure(webhook_name, meta, http_status, reason) do
    %SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Webhook.report_to_appsignal(%{
      organization_id: meta[:organization_id],
      webhook_name: webhook_name,
      flow_id: meta[:flow_id],
      contact_id: meta[:contact_id],
      http_status: http_status,
      reason: reason
    })
  end

  # Builds the failure-report metadata (org + flow context) from a webhook's fields.
  # flow_id/contact_id are present for flow-dispatched function webhooks (enriched in
  # Glific.Flows.Webhook.perform/1) and nil for internal/direct calls.
  @spec webhook_meta(non_neg_integer() | nil, map()) :: map()
  defp webhook_meta(org_id, fields) do
    %{
      organization_id: org_id,
      flow_id: fields["flow_id"],
      contact_id: fields["contact_id"]
    }
  end
end
