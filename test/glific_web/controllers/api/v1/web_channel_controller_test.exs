defmodule GlificWeb.API.V1.WebChannelControllerTest do
  @moduledoc false

  use GlificWeb.ConnCase

  alias FunWithFlags.Store.Cache, as: FlagCache
  alias Glific.{Fixtures, Partners, WebChannel.Branding}

  @branding_path "/api/v1/web_channel/branding"

  # FunWithFlags persists through Ecto but reads through a 15-minute cache, and only the Ecto
  # half rolls back with the sandbox. Flushing forces every read back to the rolled-back table,
  # so one test's enable cannot leak into the next and read as the channel being on.
  setup do
    FlagCache.flush()
    :ok
  end

  defp enable_web_channel(organization_id),
    do: FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: organization_id})

  defp add_branding(organization_id, keys) do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "web_channel",
        keys: keys,
        secrets: %{},
        is_active: true
      })

    organization_id |> Partners.get_organization!() |> Partners.fill_cache()
    :ok
  end

  describe "branding/2" do
    test "returns the organization's branding when the web channel is enabled", %{
      conn: conn,
      organization_id: organization_id
    } do
      enable_web_channel(organization_id)

      add_branding(organization_id, %{
        theme: "violet",
        logo_url: "https://cdn.example.org/logo.svg",
        display_name: "Example NGO"
      })

      assert %{
               "data" => %{
                 "theme" => "violet",
                 "logo_url" => "https://cdn.example.org/logo.svg",
                 "display_name" => "Example NGO"
               }
             } = conn |> get(@branding_path) |> json_response(200)
    end

    test "falls back to the organization name when no branding has been saved", %{
      conn: conn,
      organization_id: organization_id
    } do
      enable_web_channel(organization_id)
      organization = Partners.organization(organization_id)

      assert %{
               "data" => %{
                 "theme" => Branding.default_theme(),
                 "logo_url" => nil,
                 "display_name" => organization.name
               }
             } == conn |> get(@branding_path) |> json_response(200)
    end

    test "falls back for branding values the browser should not be asked to paint", %{
      conn: conn,
      organization_id: organization_id
    } do
      enable_web_channel(organization_id)

      add_branding(organization_id, %{
        theme: "red; background: url(evil)",
        logo_url: "http://cdn.example.org/logo.svg"
      })

      assert %{"data" => %{"theme" => "zinc", "logo_url" => nil}} =
               conn |> get(@branding_path) |> json_response(200)
    end

    test "returns 404 for an organization without the feature flag", %{conn: conn} do
      assert %{"error" => %{"status" => 404, "message" => "Web channel is not enabled."}} =
               conn |> get(@branding_path) |> json_response(404)
    end

    test "resolves the organization from the request host", %{organization_id: organization_id} do
      enable_web_channel(organization_id)
      add_branding(organization_id, %{theme: "violet", display_name: "First NGO"})

      other = Fixtures.organization_fixture(%{shortcode: "other_ngo", name: "Second NGO"})
      enable_web_channel(other.id)
      add_branding(other.id, %{theme: "amber", display_name: "Second NGO"})

      assert %{"data" => %{"theme" => "violet", "display_name" => "First NGO"}} =
               "glific.glific.test" |> branding_for_host() |> json_response(200)

      assert %{"data" => %{"theme" => "amber", "display_name" => "Second NGO"}} =
               "other_ngo.glific.test" |> branding_for_host() |> json_response(200)
    end
  end

  # The organization comes from the host via SubdomainPlug in the endpoint, so these have to go
  # through a conn that ConnCase has not already assigned an organization onto.
  defp branding_for_host(host) do
    %{Phoenix.ConnTest.build_conn() | host: host}
    |> get(@branding_path)
  end
end
