defmodule Glific.Flows.Webhooks.CreateCertificate do
  @moduledoc """
  Generates a certificate for a contact using a stored certificate template.

  Parses and validates the incoming fields, fetches the matching
  `CertificateTemplate` row, extracts the Google Slide presentation and page
  IDs from the template URL, then delegates to
  `Glific.Certificates.Certificate.generate_certificate/4`.

  Returns `{:ok, result_map}` on success (where the result map already carries
  `success: true` and `certificate_url`) or `{:error, reason}` on any failure
  so the flow engine routes to the Failure branch.
  """

  use Glific.Flows.Webhooks.Sync, name: "create_certificate"

  alias Glific.Certificates.Certificate
  alias Glific.Certificates.CertificateTemplate
  alias Glific.Repo
  alias Glific.ThirdParty.GoogleSlide.Slide

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, String.t()}
  def call(fields, ctx) do
    with {:ok, parsed_fields} <- parse_certificate_params(fields, ctx.organization_id),
         {:ok, contact_id} <- extract_contact_id(parsed_fields.contact),
         {:ok, certificate_template} <- fetch_certificate_template(parsed_fields),
         {:ok, slide_details} <- Slide.parse_slides_url(certificate_template.url) do
      result =
        Certificate.generate_certificate(
          parsed_fields,
          contact_id,
          slide_details.presentation_id,
          slide_details.page_id
        )

      case result do
        %{success: true} = success_map -> {:ok, success_map}
        %{success: false, reason: reason} -> {:error, reason}
        other -> {:error, inspect(other)}
      end
    end
  end

  @spec parse_certificate_params(map(), non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  defp parse_certificate_params(fields, org_id) do
    certificate_params_schema = %{
      certificate_id: [
        type: :integer,
        required: true,
        cast_func: fn value ->
          cond do
            is_integer(value) ->
              {:ok, value}

            is_binary(value) ->
              case Integer.parse(value) do
                {int, ""} -> {:ok, int}
                _ -> {:error, "certificate_id must be an integer"}
              end

            true ->
              {:error, "certificate_id must be an integer"}
          end
        end
      ],
      contact: [type: :map, required: true],
      replace_texts: [type: :map, required: true]
    }

    case Tarams.cast(fields, certificate_params_schema) |> Glific.handle_tarams_result() do
      {:ok, parsed} -> {:ok, Map.put(parsed, :organization_id, org_id)}
      err -> err
    end
  end

  @spec extract_contact_id(map()) :: {:ok, any()} | {:error, String.t()}
  defp extract_contact_id(contact) do
    contact_id = get_in(contact, ["id"]) || get_in(contact, [:id])

    if is_nil(contact_id) or contact_id == "" do
      {:error, "contact.id is required"}
    else
      {:ok, contact_id}
    end
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
        Glific.log_error(
          "Certificate template not found for ID: #{fields.certificate_id} and organization: #{fields.organization_id}"
        )
    end
  end
end
