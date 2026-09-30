defmodule GlificWeb.TenantsTest do
  use GlificWeb.ConnCase

  import ExUnit.CaptureLog

  alias Glific.{Fixtures, Partners.OrganizationIndex}
  alias GlificWeb.Tenants

  # Cachex is shared across the suite, so an index built here must not outlive this file. The log
  # level is raised because config/test.exs runs at :emergency, which would make the assertions
  # below that no cache load happened pass whether or not one did.
  setup do
    level = Logger.level()
    Logger.configure(level: :info)

    on_exit(fn ->
      Logger.configure(level: level)
      Cachex.del(:glific_cache, {:global, :organization_index})
    end)

    :ok
  end

  describe "tenants" do
    test "reserved_organization?/1 checks for reserved organization name" do
      assert true = Tenants.reserved_organization?("www")
      assert true = Tenants.reserved_organization?("public")
      assert true = Tenants.reserved_organization?("pg_reserved")
    end

    test "organization_handler/1 returns organization id for the correct shortcode" do
      shortcode = "org_shortcode"

      organization = Fixtures.organization_fixture(%{shortcode: shortcode, status: :active})
      assert Tenants.organization_handler(shortcode) == organization.id

      # for incorrect shortcode it should return organization id of default organization
      assert Tenants.organization_handler("wrong_shortcode") == 0

      assert Tenants.organization_handler("api") == Tenants.organization_handler()
      assert Tenants.organization_handler() > 0
    end

    test "organization_handler/1 resolves a known shortcode from the index, without a query" do
      shortcode = "indexed_org"
      organization = Fixtures.organization_fixture(%{shortcode: shortcode, status: :active})
      OrganizationIndex.refresh()

      log =
        capture_log(fn ->
          assert Tenants.organization_handler(shortcode) == organization.id
        end)

      refute log =~ "Loading organization cache"
    end

    test "organization_handler/1 rejects an unknown host without loading anything from the database" do
      Fixtures.organization_fixture(%{shortcode: "known_org", status: :active})
      OrganizationIndex.refresh()

      log =
        capture_log(fn ->
          assert Tenants.organization_handler("scanner") == 0
          assert Tenants.organization_handler("aws") == 0
        end)

      refute log =~ "Loading organization cache"
    end

    # Without this the two assertions above would hold even if the index were bypassed entirely.
    test "the absence of a cache load is a real signal, not a silent log" do
      Cachex.del(:glific_cache, {:global, :organization_index})

      log = capture_log(fn -> assert Tenants.organization_handler("scanner") == 0 end)

      assert log =~ "Loading organization cache"
    end
  end
end
