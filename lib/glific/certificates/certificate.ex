defmodule Glific.Certificates.Certificate do
  @moduledoc """
  Functions related to certificate templates and managing issued certificates
  """

  alias Glific.{
    Certificates.CertificateTemplate,
    Certificates.IssuedCertificate,
    Notifications
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

  @spec issue_certificate(
          %{
            template_id: non_neg_integer(),
            contact_id: non_neg_integer(),
            url: String.t() | nil,
            errors: map()
          },
          non_neg_integer()
        ) :: {:ok, IssuedCertificate.t()}
  @doc """
  Add an entry in issue_certificates table which helps us to track the issued certificates
  """
  def issue_certificate(attrs, organization_id) do
    {:ok, issued_certificate} =
      attrs
      |> Map.merge(%{
        certificate_template_id: attrs.template_id,
        organization_id: organization_id,
        gcs_url: attrs.url
      })
      |> IssuedCertificate.create_issued_certificate()

    if issued_certificate.errors != %{} do
      {:ok, _} = create_cert_generation_fail_notification(issued_certificate)
    end

    {:ok, issued_certificate}
  end

  @spec create_cert_generation_fail_notification(IssuedCertificate.t()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  defp create_cert_generation_fail_notification(issued_certificate) do
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
end
