defmodule Glific.Flows.Webhooks.CreateCertificateTest do
  @moduledoc """
  Unit tests for the CreateCertificate webhook implementation.

  Tests the module directly via `call/2`, covering:
  - Happy path: valid fields, template found, certificate generated
  - Missing required fields (certificate_id, contact, replace_texts, organization_id)
  - Certificate template not found
  - Invalid slide URL
  - Certificate generation failure
  """

  use Glific.DataCase, async: false

  import Mock

  alias Glific.Certificates.Certificate
  alias Glific.Certificates.CertificateTemplate
  alias Glific.Fixtures
  alias Glific.Flows.Webhooks.CreateCertificate
  alias Glific.Partners
  alias Glific.Seeds.SeedsDev
  alias Glific.ThirdParty.GoogleSlide.Slide

  @mock_presentation_id "copied_presentation123"
  @mock_copied_slide %{"id" => @mock_presentation_id}
  @mock_thumbnail %{"contentUrl" => "image_url"}

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    {:ok, _credential} =
      Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        secrets: %{
          "bucket" => "mock-bucket",
          "service_account" =>
            Jason.encode!(%{
              project_id: "test",
              private_key_id: "key",
              client_email: "test@test.com",
              private_key: "TEST PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: 1
      })

    {:ok, _credential} =
      Partners.create_credential(%{
        shortcode: "google_slides",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "test",
              private_key_id: "key",
              client_email: "test@test.com",
              private_key: "TEST PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: 1
      })

    :ok
  end

  defp certificate_template_attrs do
    %{
      label: "test",
      type: :slides,
      url: "https://docs.google.com/presentation/d/#{@mock_presentation_id}/edit#slide=id.g2",
      organization_id: 1
    }
  end

  defp mock_all_google_apis_success do
    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post,
        url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket/o",
        query: [uploadType: "multipart"]
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body:
             Jason.encode!(%{
               "name" => "uploads/certificate/#{@mock_presentation_id}/123.png",
               "mediaLink" =>
                 "https://storage.googleapis.com/mock-bucket/uploads/certificate/#{@mock_presentation_id}/123.png",
               "selfLink" =>
                 "https://storage.googleapis.com/mock-bucket/uploads/certificate/#{@mock_presentation_id}/123.png"
             })
         }}

      %{
        method: :get,
        url:
          "https://storage.googleapis.com/mock-bucket/uploads/certificate/#{@mock_presentation_id}/123.png"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}

      %{
        method: :post,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

      %{
        method: :post,
        url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :post,
        url: "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :get,
        url:
          "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

      %{
        method: :get,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}

      %{method: :get, url: "image_url"} ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}
    end)
  end

  describe "call/2 - happy path" do
    test "returns {:ok, result_map} with certificate_url on success" do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
        end
      ) do
        mock_all_google_apis_success()

        {:ok, certificate} =
          CertificateTemplate.create_certificate_template(certificate_template_attrs())

        contact = Fixtures.contact_fixture()

        fields = %{
          "certificate_id" => certificate.id,
          "contact" => %{"id" => contact.id},
          "organization_id" => 1,
          "replace_texts" => %{"{1}" => "Test User", "{2}" => "2025"}
        }

        assert {:ok, result} = CreateCertificate.call(fields, %{organization_id: 1})
        assert result.success == true
        assert is_binary(result.certificate_url)
      end
    end
  end

  describe "call/2 - validation failures" do
    test "returns {:error, message} when required fields are missing" do
      assert {:error, msg} = CreateCertificate.call(%{}, %{organization_id: 1})
      assert is_binary(msg)
      # All required fields are missing
      assert msg =~ "is required"
    end

    test "returns {:error, message} when replace_texts is not a map" do
      fields = %{
        "certificate_id" => "1",
        "organization_id" => 1,
        "contact" => %{"id" => "123"},
        "replace_texts" => "John Doe"
      }

      assert {:error, msg} = CreateCertificate.call(fields, %{organization_id: 1})
      assert msg =~ "replace_texts"
    end

    test "returns {:error, message} when contact is missing" do
      fields = %{
        "certificate_id" => "1",
        "organization_id" => 1,
        "replace_texts" => %{"{1}" => "John"}
      }

      assert {:error, msg} = CreateCertificate.call(fields, %{organization_id: 1})
      assert msg =~ "contact"
    end
  end

  describe "call/2 - certificate template not found" do
    test "returns {:error, message} when certificate_id does not match any template" do
      nonexistent_id = 99_999

      fields = %{
        "certificate_id" => nonexistent_id,
        "contact" => %{"id" => "123"},
        "organization_id" => 1,
        "replace_texts" => %{}
      }

      assert {:error, msg} = CreateCertificate.call(fields, %{organization_id: 1})
      assert msg =~ "Certificate template not found"
      assert msg =~ to_string(nonexistent_id)
    end
  end

  describe "call/2 - slide URL parse failure" do
    test "returns {:error, message} when Slide.parse_slides_url fails during webhook call" do
      # First, create the certificate template with a working Goth mock so the
      # changeset's Slide.get_file call succeeds. Then replace the mock to simulate
      # a failure only during the webhook call itself.
      certificate =
        with_mock(Goth.Token, [],
          fetch: fn _url ->
            {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
          end
        ) do
          Tesla.Mock.mock(fn
            %{
              method: :get,
              url:
                "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
            } ->
              {:ok, %Tesla.Env{status: 200, body: ""}}
          end)

          {:ok, cert} =
            CertificateTemplate.create_certificate_template(certificate_template_attrs())

          cert
        end

      with_mock(Slide, [:passthrough],
        parse_slides_url: fn _url -> {:error, "Invalid Google Slides URL"} end
      ) do
        fields = %{
          "certificate_id" => certificate.id,
          "contact" => %{"id" => "123"},
          "organization_id" => 1,
          "replace_texts" => %{}
        }

        assert {:error, "Invalid Google Slides URL"} =
                 CreateCertificate.call(fields, %{organization_id: 1})
      end
    end
  end

  describe "call/2 - certificate generation failure" do
    test "returns {:error, reason} when Certificate.generate_certificate returns success: false" do
      certificate =
        with_mocks([
          {Goth.Token, [],
           [
             fetch: fn _url ->
               {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
             end
           ]},
          {Slide, [:passthrough],
           [
             parse_slides_url: fn _url ->
               {:ok, %{presentation_id: @mock_presentation_id, page_id: "g2"}}
             end,
             get_file: fn _org_id, _pres_id -> {:ok, %{}} end
           ]}
        ]) do
          {:ok, cert} =
            CertificateTemplate.create_certificate_template(certificate_template_attrs())

          cert
        end

      with_mocks([
        {Slide, [:passthrough],
         [
           parse_slides_url: fn _url ->
             {:ok, %{presentation_id: @mock_presentation_id, page_id: "g2"}}
           end
         ]},
        {Certificate, [:passthrough],
         [
           generate_certificate: fn _fields, _contact_id, _pres_id, _page_id ->
             %{success: false, reason: "Failed to generate certificate"}
           end
         ]}
      ]) do
        fields = %{
          "certificate_id" => certificate.id,
          "contact" => %{"id" => "123"},
          "organization_id" => 1,
          "replace_texts" => %{}
        }

        assert {:error, "Failed to generate certificate"} =
                 CreateCertificate.call(fields, %{organization_id: 1})
      end
    end
  end
end
