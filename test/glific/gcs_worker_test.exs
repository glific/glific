defmodule Glific.GcsWorkerTest do
  use GlificWeb.ConnCase
  import Mock

  alias Glific.{
    Partners,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  @tag :upload
  test "upload_media/3", attrs do
    Application.put_env(:waffle, :token_fetcher, Glific.GCS)

    body = %{
      error: "invalid_grant",
      error_description: "Invalid grant: account not found"
    }

    body = Jason.encode!(body)

    err_response = """
    unexpected status 400 from Google

    #{body}
    """

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:error, RuntimeError.exception(err_response)}
      end
    ) do
      valid_attrs = %{
        shortcode: "google_cloud_storage",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: attrs.organization_id
      }

      Glific.Caches.remove(attrs.organization_id, [{:provider_token, "google_cloud_storage"}])

      {:ok, _credential} = Partners.create_credential(valid_attrs)

      assert nil ==
               Partners.get_goth_token(attrs.organization_id, "google_cloud_storage")
    end
  end
end
