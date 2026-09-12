defmodule GlificWeb.API.V1.WebChannelControllerTest do
  @moduledoc false

  use GlificWeb.ConnCase

  import Mock

  alias FunWithFlags.Store.Cache, as: FlagCache
  alias Glific.{Fixtures, Partners, WebChannel.Branding}

  import Glific.WebChannelFlagHelpers, only: [activate_web_channel: 1, activate_web_channel: 2]

  @branding_path "/api/v1/web_channel/branding"

  # FunWithFlags persists through Ecto but reads through a 15-minute cache, and only the Ecto
  # half rolls back with the sandbox. Flushing forces every read back to the rolled-back table,
  # so one test's enable cannot leak into the next and read as the channel being on.
  setup do
    FlagCache.flush()
    :ok
  end

  # Both halves of the switch: the Glific flag, and the organization's own active credential.
  defp enable_web_channel(organization_id) do
    FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: organization_id})
    activate_web_channel(organization_id)
  end

  defp add_branding(organization_id, keys), do: activate_web_channel(organization_id, keys)

  defp deactivate_web_channel(organization_id) do
    {:ok, credential} =
      Partners.get_credential(%{organization_id: organization_id, shortcode: "web_channel"})

    Partners.update_credential(credential, %{is_active: false})
    organization_id |> Partners.organization() |> Partners.fill_cache()
    :ok
  end

  describe "branding/2" do
    test "returns the organization's branding when the web channel is enabled", %{
      conn: conn,
      organization_id: organization_id
    } do
      enable_web_channel(organization_id)

      add_branding(organization_id, %{
        primary_color: "#4C3BCF",
        secondary_color: "#FF8A3D",
        logo_url: "https://cdn.example.org/logo.png",
        display_name: "Example NGO",
        about_website: "example.org"
      })

      assert %{
               "data" => %{
                 "primary_color" => "#4c3bcf",
                 "primary_foreground" => _foreground,
                 "secondary_color" => "#ff8a3d",
                 "logo_url" => "https://cdn.example.org/logo.png",
                 "display_name" => "Example NGO",
                 "about" => %{"website" => "https://example.org"}
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
                 "primary_color" => Branding.default_primary(),
                 "primary_foreground" => Branding.readable_on(Branding.default_primary()),
                 "secondary_color" => Branding.default_secondary(),
                 "logo_url" => nil,
                 "display_name" => organization.name,
                 "about" => %{
                   "description" => nil,
                   "address" => nil,
                   "website" => nil,
                   "email" => nil,
                   "hours" => nil
                 }
               }
             } == conn |> get(@branding_path) |> json_response(200)
    end

    test "falls back for branding values the browser should not be asked to paint", %{
      conn: conn,
      organization_id: organization_id
    } do
      enable_web_channel(organization_id)

      add_branding(organization_id, %{
        primary_color: "red; background: url(evil)",
        logo_url: "http://cdn.example.org/logo.png"
      })

      assert %{"data" => %{"primary_color" => primary, "logo_url" => nil}} =
               conn |> get(@branding_path) |> json_response(200)

      assert primary == Branding.default_primary()
    end

    test "returns 404 rather than raising when the organization cannot be loaded", %{conn: conn} do
      # organization/1 returns {:error, _} on a cache or lookup failure, and everything
      # downstream reads organization.id. This is a public endpoint, so it must not 500.
      with_mock Partners, [:passthrough], organization: fn _id -> {:error, "cache miss"} end do
        assert %{"error" => %{"status" => 404}} =
                 conn |> get(@branding_path) |> json_response(404)
      end
    end

    test "returns 404 for an organization without the feature flag", %{conn: conn} do
      assert %{"error" => %{"status" => 404, "message" => "Web channel is not enabled."}} =
               conn |> get(@branding_path) |> json_response(404)
    end

    # The flag is Glific's half of the switch. An organization that has been granted the feature
    # and then switched it off in Settings must be just as unreachable.
    test "returns 404 once the organization switches the channel off", %{
      conn: conn,
      organization_id: organization_id
    } do
      enable_web_channel(organization_id)
      assert %{"data" => _branding} = conn |> get(@branding_path) |> json_response(200)

      deactivate_web_channel(organization_id)

      assert %{"error" => %{"status" => 404, "message" => "Web channel is not enabled."}} =
               conn |> get(@branding_path) |> json_response(404)
    end

    test "resolves the organization from the request host", %{organization_id: organization_id} do
      enable_web_channel(organization_id)
      add_branding(organization_id, %{primary_color: "#4c3bcf", display_name: "First NGO"})

      other = Fixtures.organization_fixture(%{shortcode: "other_ngo", name: "Second NGO"})
      enable_web_channel(other.id)
      add_branding(other.id, %{primary_color: "#ffb900", display_name: "Second NGO"})

      assert %{"data" => %{"primary_color" => "#4c3bcf", "display_name" => "First NGO"}} =
               "glific.glific.test" |> branding_for_host() |> json_response(200)

      assert %{"data" => %{"primary_color" => "#ffb900", "display_name" => "Second NGO"}} =
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
