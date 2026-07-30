defmodule Glific.Flows.Webhooks.CreateCertificate do
  @moduledoc """
  Generate a certificate for a contact (`create_certificate` node).
  """

  use Glific.Flows.Webhooks.Sync, name: "create_certificate"

  require Logger

  alias Glific.{
    Certificates.Certificate,
    Certificates.CertificateTemplate,
    Flows.Webhooks.ErrorType,
    Repo,
    ThirdParty.GoogleSlide.Slide
  }

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def call(fields, _ctx) do
    with {:ok, parsed_fields} <- parse_certificate_params(fields),
         {:ok, certificate_template} <- fetch_certificate_template(parsed_fields),
         {:ok, slide_details} <-
           Slide.parse_slides_url(certificate_template.url) do
      # A generation failure (Google Slides / GCS) is a real failure → typed error to Failure.
      case Certificate.generate_certificate(
             parsed_fields,
             parsed_fields.contact["id"],
             slide_details.presentation_id,
             slide_details.page_id
           ) do
        %{success: false, reason: reason} -> {:error, :unknown, reason}
        result -> {:ok, result}
      end
    else
      {:error, error_type, message} when is_atom(error_type) ->
        {:error, error_type, message}

      {:error, message} ->
        {:error, :unknown, message}
    end
  end

  @spec parse_certificate_params(map()) :: {:ok, map()} | {:error, ErrorType.t(), String.t()}
  defp parse_certificate_params(fields) do
    certificate_params_schema = %{
      certificate_id: [
        type: :integer,
        required: true,
        cast_func: fn value ->
          # Must not raise — that would escape call/2 and crash the Oban job.
          if is_binary(value) do
            case Glific.parse_maybe_integer(value) do
              {:ok, integer} -> {:ok, integer}
              :error -> {:error, "must be a valid integer"}
            end
          else
            {:ok, value}
          end
        end
      ],
      contact: [type: :map, required: true],
      replace_texts: [type: :map, required: true],
      organization_id: [type: :integer, required: true]
    }

    case Tarams.cast(fields, certificate_params_schema) |> Glific.handle_tarams_result() do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, :invalid_input, reason}
    end
  end

  @spec fetch_certificate_template(map()) ::
          {:ok, CertificateTemplate.t()} | {:error, ErrorType.t(), String.t()}
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

        {:error, :invalid_input,
         "Certificate template not found for ID: #{fields.certificate_id}"}
    end
  end
end
