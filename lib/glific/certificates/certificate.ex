defmodule Glific.Certificates.Certificate do
  @moduledoc """
  Functions related to certificate templates and managing issued certificates
  """

  alias Glific.{
    Certificates.CertificateTemplate,
    Certificates.IssuedCertificate,
    GCS.GcsWorker,
    Notifications,
    ThirdParty.GoogleSlide.Slide
  }

  @doc """
  Creates a certificate template
  """
  @spec create_certificate_template(map()) :: {:ok, map()} | {:error, any()}
  def create_certificate_template(params) do
    # Internally we have `type` of url, although we only support slides now
    params = Map.put_new(params, :type, :slides)

    with {:ok, cert_template} <- CertificateTemplate.create_certificate_template(params) do
      {:ok, %{certificate_template: cert_template}}
    end
  end

  @doc """
  Generates the certificate url and link with the contact and certificate template
  """
  @spec generate_certificate(map(), integer(), String.t(), String.t()) :: map()
  def generate_certificate(fields, contact_id, presentation_id, slide_id) do
    with {:ok, thumbnail} <-
           Slide.create_certificate(
             fields.organization_id,
             presentation_id,
             fields.replace_texts,
             slide_id
           ),
         {:ok, image} <-
           download_file(thumbnail, presentation_id, contact_id, fields.organization_id) do
      {:ok, _} =
        issue_certificate(
          %{
            template_id: fields.certificate_id,
            contact_id: contact_id,
            url: image,
            errors: %{}
          },
          fields.organization_id
        )

      %{success: true, certificate_url: image}
    else
      {:error, error} ->
        {:ok, _} =
          issue_certificate(
            %{
              template_id: fields.certificate_id,
              contact_id: contact_id,
              url: nil,
              errors: %{reason: error}
            },
            fields.organization_id
          )

        %{success: false, reason: error}
    end
  end

  @spec issue_certificate(
          %{
            template_id: non_neg_integer(),
            contact_id: non_neg_integer(),
            url: String.t() | nil,
            errors: map()
          },
          non_neg_integer()
        ) :: {:ok, IssuedCertificate.t()}
  # Add an entry in issue_certificates table which helps us to track the issued certificates
  defp issue_certificate(attrs, organization_id) do
    {:ok, issued_certificate} =
      attrs
      |> Map.merge(%{
        certificate_template_id: attrs.template_id,
        organization_id: organization_id,
        gcs_url: attrs.url
      })
      |> IssuedCertificate.create_issued_certificate()

    if issued_certificate.errors != %{} do
      {:ok, _} = notify_certificate_generation(issued_certificate)
    end

    {:ok, issued_certificate}
  end

  @spec notify_certificate_generation(IssuedCertificate.t()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  defp notify_certificate_generation(issued_certificate) do
    Notifications.create_notification(%{
      category: "Custom Certificates",
      message: """
      Custom certificate generation with template_id: #{issued_certificate.certificate_template_id} failed
      for contact_id: #{issued_certificate.contact_id} due to #{issued_certificate.errors.reason}.
      """,
      severity: Notifications.types().warning,
      organization_id: issued_certificate.organization_id,
      entity: %{
        template_id: issued_certificate.certificate_template_id,
        contact_id: issued_certificate.contact_id
      }
    })
  end

  @spec download_file(String.t(), String.t(), integer(), integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp download_file(thumbnail_url, presentation_id, contact_id, org_id) do
    uuid = Ecto.UUID.generate()
    img_timestamp = Timex.now() |> Timex.format!("%Y_%m_%d_%H_%M_%S", :strftime)
    remote_name = "certificate/#{presentation_id}/#{img_timestamp}_#{contact_id}.png"

    temp_path = Path.join(System.tmp_dir!(), "#{uuid}.png")

    with {:ok, %Tesla.Env{status: 200, body: image_data}} <- Tesla.get(thumbnail_url),
         :ok <- File.write(temp_path, image_data),
         {:ok, media_meta} <- GcsWorker.upload_media(temp_path, remote_name, org_id) do
      File.rm(temp_path)
      {:ok, media_meta.url}
    else
      {:error, reason} ->
        File.rm(temp_path)
        {:error, "#{inspect(reason)}"}

      {:ok, %Tesla.Env{status: status}} when status != 200 ->
        {:error, "Failed to download thumbnail url"}
    end
  end
end
