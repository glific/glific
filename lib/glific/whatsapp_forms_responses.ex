defmodule Glific.WhatsappFormsResponses do
  @moduledoc """
  Module to handle WhatsApp Form Responses
  """
  import Ecto.Query, warn: false
  use Publicist
  require Logger

  alias Glific.{
    Flows.FlowContext,
    GCS.GcsWorker,
    Messages.Message,
    Providers.Gupshup.PartnerAPI,
    Repo,
    SafeLog,
    Sheets,
    Sheets.GoogleSheets,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse,
    WhatsappForms.WhatsappFormWorker
  }

  @doc """
  Create a WhatsApp form response from the given attributes
  """
  @spec create_whatsapp_form_response(map()) ::
          {:ok, WhatsappFormResponse.t()} | {:error, Ecto.Changeset.t() | String.t() | any()}
  def create_whatsapp_form_response(attrs) do
    with {:ok, whatsapp_form} <- get_whatsapp_form(attrs.context_id, attrs.organization_id),
         {:ok, parsed_timestamp} <- parse_timestamp(attrs.submitted_at),
         {:ok, decoded_response} <- Jason.decode(attrs.raw_response),
         {:ok, result} <-
           do_create_whatsapp_form_response(%{
             raw_response: decoded_response,
             contact_id: attrs.sender_id,
             submitted_at: parsed_timestamp,
             whatsapp_form_id: whatsapp_form.id,
             organization_id: attrs.organization_id
           }) do
      payload = %{
        whatsapp_form_response_id: result.id,
        raw_response: result.raw_response,
        submitted_at: result.submitted_at,
        whatsapp_form_id: result.whatsapp_form_id,
        organization_id: result.organization_id,
        whatsapp_form_name: whatsapp_form.name,
        contact_number: attrs.sender.phone
      }

      WhatsappFormWorker.enqueue_write_to_sheet(whatsapp_form, payload)

      {:ok, result}
    end
  end

  @spec get_whatsapp_form(String.t(), non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  defp get_whatsapp_form(context_id, org_id) do
    with {:ok, previous_message} <-
           Repo.fetch_by(Message, %{bsp_message_id: context_id, organization_id: org_id}),
         %{template: template} <- Repo.preload(previous_message, [:template]),
         [%{"flow_id" => flow_id}] <- template.buttons,
         wa_form when not is_nil(wa_form) <- Repo.get_by(WhatsappForm, %{meta_flow_id: flow_id}) do
      {:ok, wa_form}
    else
      _ -> {:error, "WhatsApp Form not found for the given template_id"}
    end
  end

  @spec parse_timestamp(String.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  defp parse_timestamp(timestamp) do
    DateTime.from_unix(String.to_integer(timestamp))
  end

  @spec do_create_whatsapp_form_response(any()) ::
          {:ok, WhatsappFormResponse.t()} | {:error, any()}
  defp do_create_whatsapp_form_response(attrs) do
    %WhatsappFormResponse{}
    |> WhatsappFormResponse.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Write WhatsApp form response to Google Sheet.
  """
  @spec write_to_google_sheet(map(), WhatsappForm.t()) ::
          {:ok, map()} | {:error, any()}
  def write_to_google_sheet(response, %{sheet_id: sheet_id} = whatsapp_form)
      when not is_nil(sheet_id) do
    organization_id = response["organization_id"]

    Glific.Metrics.increment("Whatsapp Form Response Sheet Write", organization_id)

    with spreadsheet_id <- get_spreadsheet_id(whatsapp_form),
         {:ok, ordered_row} <- prepare_row_from_headers(response, spreadsheet_id),
         {:ok, values} <-
           insert_row_in_sheet(organization_id, spreadsheet_id, ordered_row) do
      {:ok, values}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def write_to_google_sheet(response, _whatsapp_form) do
    {:ok, response}
  end

  @spec get_spreadsheet_id(WhatsappForm.t()) :: String.t()
  defp get_spreadsheet_id(whatsapp_form) do
    whatsapp_form = Repo.preload(whatsapp_form, [:sheet])
    Sheets.extract_spreadsheet_id(whatsapp_form.sheet.url)
  end

  @spec insert_row_in_sheet(non_neg_integer(), String.t(), list(String.t())) ::
          {:ok, any()} | {:error, any()}
  defp insert_row_in_sheet(organization_id, spreadsheet_id, values) do
    GoogleSheets.insert_row(organization_id, spreadsheet_id, %{
      range: "A:A",
      data: [values]
    })

    {:ok, values}
  end

  @doc """
  Downloads any media uploaded through a WhatsApp form (PhotoPicker / DocumentPicker)
  to GCS and rewrites each media entry in `raw_response` with its public `gcs_url`.

  A media field is a list of maps shaped like
  `%{"id" => 913.., "file_name" => "x.jpg", "mime_type" => "image/jpeg", "sha256" => ".."}`.
  Non-media fields (strings, multi-select lists) are returned untouched. Any single
  download/upload failure is logged and leaves that entry as-is, so one bad photo
  never blocks the rest of the response.
  """
  @spec save_response_media(map(), non_neg_integer()) :: map()
  def save_response_media(raw_response, organization_id) when is_map(raw_response) do
    Map.new(raw_response, fn
      {key, value} when is_list(value) ->
        if media_list?(value),
          do: {key, Enum.map(value, &save_one_media(&1, organization_id))},
          else: {key, value}

      kv ->
        kv
    end)
  end

  def save_response_media(raw_response, _organization_id), do: raw_response

  @spec media_list?(list()) :: boolean()
  defp media_list?([%{"id" => _, "mime_type" => _} | _]), do: true
  defp media_list?(_), do: false

  @spec save_one_media(map(), non_neg_integer()) :: map()
  # Already uploaded (e.g. on an Oban retry sourced from the persisted row) — skip
  # the re-download/re-upload so the gcs_url stays stable and we don't burn the
  # Gupshup media rate limit.
  defp save_one_media(%{"gcs_url" => gcs_url} = media, _organization_id)
       when is_binary(gcs_url),
       do: media

  defp save_one_media(%{"id" => id, "file_name" => file_name} = media, organization_id) do
    # Deterministic key (media id) so a retried upload overwrites the same object
    # instead of orphaning the first one under a fresh UUID.
    remote = "whatsapp_forms/#{organization_id}/#{id}-#{file_name}"
    local = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{file_name}")

    with {:ok, bytes} <- PartnerAPI.download_flow_media(organization_id, id),
         :ok <- File.write(local, bytes),
         {:ok, %{url: gcs_url}} <- GcsWorker.upload_media(local, remote, organization_id) do
      Map.put(media, "gcs_url", gcs_url)
    else
      error ->
        Logger.error(
          "Failed to save WhatsApp form media #{file_name} (id #{id}): #{SafeLog.safe_inspect(error)}"
        )

        media
    end
  end

  defp save_one_media(media, _organization_id), do: media

  @doc """
  Injects the saved media URLs (gcs_url) into the contact's active flow result
  variables, so a flow can read e.g. `@results.<name>.photos` as the GCS URL after
  a short wait node.

  This runs in the async worker after the media has been uploaded to GCS. It finds
  every active flow context for the contact and updates any result entry that holds
  a media field (e.g. `photos`) with the comma-joined gcs_url(s). Fields whose upload
  failed are skipped, so the flow keeps the original value rather than a bad URL.
  """
  @spec inject_media_into_flow_results(map()) :: :ok
  def inject_media_into_flow_results(payload) do
    media_values = media_field_values(Map.get(payload, "raw_response", %{}))

    with false <- media_values == %{},
         id when not is_nil(id) <- Map.get(payload, "whatsapp_form_response_id"),
         %WhatsappFormResponse{contact_id: contact_id} <- Repo.get(WhatsappFormResponse, id) do
      FlowContext
      |> where([fc], fc.contact_id == ^contact_id and is_nil(fc.completed_at))
      |> Repo.all()
      |> Repo.preload(:flow)
      |> Enum.each(&merge_media_into_results(&1, media_values))

      :ok
    else
      _ -> :ok
    end
  end

  # Builds %{field => "gcs_url1, gcs_url2"} only for media fields where EVERY item
  # uploaded successfully. A partial failure omits the field entirely, so the flow
  # keeps its original value rather than a mixed "url, {json}" string.
  @spec media_field_values(map()) :: map()
  defp media_field_values(raw_response) when is_map(raw_response) do
    raw_response
    |> Enum.filter(fn {_key, value} ->
      media_list?(value) and Enum.all?(value, &Map.has_key?(&1, "gcs_url"))
    end)
    |> Map.new(fn {key, value} ->
      {key, Enum.map_join(value, ", ", & &1["gcs_url"])}
    end)
  end

  @spec merge_media_into_results(FlowContext.t(), map()) :: any()
  defp merge_media_into_results(%FlowContext{results: results} = context, media_values)
       when is_map(results) do
    updates =
      results
      |> Enum.filter(fn {_key, value} -> is_map(value) end)
      |> Enum.reduce(%{}, fn {result_key, result_map}, acc ->
        overlap = Map.take(media_values, Map.keys(result_map))
        if overlap == %{}, do: acc, else: Map.put(acc, result_key, Map.merge(result_map, overlap))
      end)

    if updates != %{}, do: FlowContext.update_results(context, updates)
  end

  defp merge_media_into_results(_context, _media_values), do: :ok

  @spec prepare_row_from_headers(map(), String.t()) ::
          {:ok, list(String.t())} | {:error, any()}
  defp prepare_row_from_headers(response, spreadsheet_id) do
    organization_id = response["organization_id"]
    raw_response = response["raw_response"]

    payload =
      raw_response
      |> Map.delete("flow_token")
      |> Map.put("contact_phone_number", response["contact_number"])
      |> Map.put("timestamp", response["submitted_at"])
      |> Map.put("whatsapp_form_id", response["whatsapp_form_id"])
      |> Map.put("whatsapp_form_name", response["whatsapp_form_name"])

    with {:ok, headers} <- GoogleSheets.get_headers(organization_id, spreadsheet_id) do
      ordered_row =
        Enum.map(headers, fn header ->
          value = Map.get(payload, header, "")

          cond do
            is_list(value) ->
              Enum.map_join(value, ", ", fn
                item when is_map(item) -> Jason.encode!(item)
                item -> to_string(item)
              end)

            is_map(value) ->
              Jason.encode!(value)

            true ->
              value
          end
        end)

      {:ok, ordered_row}
    end
  end
end
