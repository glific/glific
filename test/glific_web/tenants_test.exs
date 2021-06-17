defmodule GlificWeb.TenantsTest do
  use GlificWeb.ConnCase

  alias Glific.Fixtures
  alias GlificWeb.Tenants

  describe "tenants" do
    test "reserved_organization?/1 checks for reserved organization name" do
      assert true = Tenants.reserved_organization?("www")
      assert true = Tenants.reserved_organization?("public")
      assert true = Tenants.reserved_organization?("pg_reserved")
    end

    test "organization_handler/1 returns organization id for the currect shortcode" do
      shortcode = "org_shortcode"

      organization = Fixtures.organization_fixture(%{shortcode: shortcode, status: :active})
      assert Tenants.organization_handler(shortcode) == organization.id

      # for incorrect shortcode it should return organization id of default organization
      assert Tenants.organization_handler("wrong_shortcode") == 0

      assert Tenants.organization_handler("api") == Tenants.organization_handler()
      assert Tenants.organization_handler() > 0
    end
  end
end
