defmodule Glific.Flows.Webhooks.CreateCertificate do
  @moduledoc """
  Generate a certificate for a contact (`create_certificate` flow-webhook node).

  Migrated from `Glific.Clients.CommonWebhook.webhook("create_certificate", ...)` onto the
  central `Glific.Flows.Webhooks` framework; behaviour is preserved one-for-one. Failure
  reporting and latency telemetry are added by `Glific.Flows.Webhooks.Dispatcher`, not here.
  """

  use Glific.Flows.Webhooks.Sync, name: "create_certificate"

  require Logger

  alias Glific.{
    Certificates.Certificate,
    Certificates.CertificateTemplate,
    Repo,
    ThirdParty.GoogleSlide.Slide
  }

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) :: map() | String.t()
  def call(fields, _ctx) do
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
end
