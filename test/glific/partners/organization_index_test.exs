defmodule Glific.Partners.OrganizationIndexTest do
  use Glific.DataCase, async: false

  alias Glific.{Fixtures, Partners, Partners.Organization, Partners.OrganizationIndex, Repo}

  # The index lives in Cachex, which is shared across the suite, so it must be gone again
  # afterwards or every later test resolves tenants against this test's rolled back data.
  setup do
    on_exit(fn -> Cachex.del(:glific_cache, {:global, :organization_index}) end)
    :ok
  end

  test "fetch/1 returns the organization id for a known active shortcode" do
    organization = Partners.organization(1)
    OrganizationIndex.refresh()

    assert {:ok, organization.id} == OrganizationIndex.fetch(organization.shortcode)
  end

  test "fetch/1 returns :error for an unknown shortcode without querying" do
    OrganizationIndex.refresh()

    assert :error == OrganizationIndex.fetch("scanner")
  end

  test "fetch/1 returns :error for a shortcode that is not active" do
    organization = Fixtures.organization_fixture(%{shortcode: "inactive_org", status: :inactive})
    OrganizationIndex.refresh()

    assert :error == OrganizationIndex.fetch(organization.shortcode)
  end

  test "fetch/1 reports :unavailable before the index has been loaded" do
    Cachex.del(:glific_cache, {:global, :organization_index})

    assert :unavailable == OrganizationIndex.fetch("glific")
  end

  test "a shortcode rename is reflected in the index, not the pre-update value" do
    Application.put_env(:glific, :refresh_organization_index, true)
    on_exit(fn -> Application.put_env(:glific, :refresh_organization_index, false) end)

    organization = Fixtures.organization_fixture(%{shortcode: "before_rename", status: :active})
    OrganizationIndex.refresh()
    assert {:ok, organization.id} == OrganizationIndex.fetch("before_rename")

    {:ok, _updated} = Partners.update_organization(organization, %{shortcode: "after_rename"})

    assert {:ok, organization.id} == OrganizationIndex.fetch("after_rename")
    assert :error == OrganizationIndex.fetch("before_rename")
  end

  test "refresh/0 does not publish an empty index over a loaded one" do
    OrganizationIndex.refresh()
    assert {:ok, _id} = OrganizationIndex.fetch("glific")

    Repo.delete_all(Organization, skip_organization_id: true)

    assert %{} == OrganizationIndex.refresh()
    assert {:ok, _id} = OrganizationIndex.fetch("glific")
  end

  test "refresh/0 leaves an empty database unresolved rather than rejecting every host" do
    Cachex.del(:glific_cache, {:global, :organization_index})
    Repo.delete_all(Organization, skip_organization_id: true)

    OrganizationIndex.refresh()

    assert :unavailable == OrganizationIndex.fetch("glific")
  end

  test "refresh/1 picks up an organization added after the last load" do
    OrganizationIndex.refresh()
    assert :error == OrganizationIndex.fetch("late_org")

    Fixtures.organization_fixture(%{shortcode: "late_org"})
    OrganizationIndex.refresh()

    assert {:ok, _id} = OrganizationIndex.fetch("late_org")
  end
end
