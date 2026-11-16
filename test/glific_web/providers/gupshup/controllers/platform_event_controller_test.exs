defmodule GlificWeb.Providers.Gupshup.Controllers.PlatformEventControllerTest do
  use GlificWeb.ConnCase
  use Oban.Testing, repo: Glific.Repo

  import Mock

  alias Glific.Messages.Message
  alias Glific.Partners
  alias Glific.Providers.Gupshup.Instrumentation
  alias Glific.Repo
  alias Glific.Seeds.SeedsDev

  @platform_event_request_params %{
    "app" => "MyBusinessApp",
    "appId" => "0a6f5e4d-1234-4c8b-9f21-7d3e5a9b1c40",
    "timestamp" => 1_760_440_000_000,
    "version" => 2,
    "type" => "platform-event",
    "payload" => %{"type" => "connectivity-check", "initiator" => "gupshup"}
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "handler" do
    test "connectivity-check is acknowledged and counted without side effects", %{conn: conn} do
      message_count = Repo.aggregate(Message, :count)

      with_mock Instrumentation, [:passthrough], track_platform_event: fn _, _ -> :ok end do
        conn = post(conn, "/gupshup", @platform_event_request_params)

        assert response(conn, 200) == ""

        assert_called(
          Instrumentation.track_platform_event(
            "connectivity-check",
            conn.assigns[:organization_id]
          )
        )
      end

      assert all_enqueued(prefix: "global") == []
      assert Repo.aggregate(Message, :count) == message_count
    end

    test "unknown sub-type is acknowledged and counted under its type", %{conn: conn} do
      params = put_in(@platform_event_request_params, ["payload", "type"], "some-future-check")

      with_mock Instrumentation, [:passthrough], track_platform_event: fn _, _ -> :ok end do
        conn = post(conn, "/gupshup", params)

        assert response(conn, 200) == ""

        assert_called(
          Instrumentation.track_platform_event(
            "some-future-check",
            conn.assigns[:organization_id]
          )
        )
      end
    end

    test "inactive organization is acknowledged but not counted", %{conn: conn} do
      organization = Partners.organization(conn.assigns[:organization_id])
      {:ok, _organization} = Partners.update_organization(organization, %{status: :suspended})

      with_mock Instrumentation, [:passthrough], track_platform_event: fn _, _ -> :ok end do
        conn = post(conn, "/gupshup", @platform_event_request_params)

        assert response(conn, 200) == ""
        assert_not_called(Instrumentation.track_platform_event(:_, :_))
      end
    end
  end

  describe "unknown event type" do
    test "is acknowledged without side effects", %{conn: conn} do
      message_count = Repo.aggregate(Message, :count)
      params = %{@platform_event_request_params | "type" => "some-future-event"}

      conn = post(conn, "/gupshup", params)

      assert response(conn, 200) == ""
      assert all_enqueued(prefix: "global") == []
      assert Repo.aggregate(Message, :count) == message_count
    end
  end
end
