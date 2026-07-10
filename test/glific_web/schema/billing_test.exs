defmodule GlificWeb.Schema.BillingTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias Glific.{
    Fixtures,
    Partners.Billing,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/billings/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/billings/list.gql")
  load_gql(:list_by_org, GlificWeb.Schema, "assets/gql/billings/list_by_org.gql")
  load_gql(:customer_portal, GlificWeb.Schema, "assets/gql/billings/customer_portal.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/billings/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/billings/create.gql")
  load_gql(:create_subscription, GlificWeb.Schema, "assets/gql/billings/create_subscription.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/billings/update.gql")
  load_gql(:payment_method, GlificWeb.Schema, "assets/gql/billings/payment_method.gql")
  load_gql(:get_coupon, GlificWeb.Schema, "assets/gql/billings/get_coupon.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/billings/delete.gql")

  test "delete a billing", %{user: user} do
    name = "Billing name"
    {:ok, billing} = Repo.fetch_by(Billing, %{name: name, organization_id: user.organization_id})
    result = auth_query_gql_by(:delete, user, variables: %{"id" => billing.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteBilling", "errors"]) == nil
  end

  test "update a billing", %{user: user} do
    name = "Billing name"

    use_cassette "update_billing" do
      {:ok, billing} =
        Repo.fetch_by(Billing, %{name: name, organization_id: user.organization_id})

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "id" => billing.id,
            "input" => %{
              "email" => "testingbilling@gmail.com"
            }
          }
        )

      assert {:ok, query_data} = result
      email = get_in(query_data, [:data, "updateBilling", "billing", "email"])
      assert email == "testingbilling@gmail.com"
    end
  end

  test "create a billing", %{user: user} do
    use_cassette "create_billing" do
      result =
        auth_query_gql_by(:create, user,
          variables: %{
            "input" => %{
              "name" => "test billing name",
              "email" => "testbilling@gmail.com",
              "currency" => "inr"
            }
          }
        )

      assert {:ok, query_data} = result
      currency = get_in(query_data, [:data, "createBilling", "billing", "currency"])
      assert currency == "inr"
      email = get_in(query_data, [:data, "createBilling", "billing", "email"])
      assert email == "testbilling@gmail.com"
    end
  end

  test "validate coupon", %{user: user} do
    use_cassette "coupon_code" do
      result =
        auth_query_gql_by(:get_coupon, user,
          variables: %{
            "code" => "P3MU8SEB"
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "getCouponCode", "code"]) == "P3MU8SEB"
      assert get_in(query_data, [:data, "getCouponCode", "id"]) == "mWH5sXEw"
    end
  end

  test "create a billing subscription", %{user: user} do
    use_cassette "create_subscription" do
      result =
        auth_query_gql_by(:create_subscription, user,
          variables: %{
            "StripePaymentMethodId" => "some_stripe_payment_method_id"
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "createBillingSubscription", "errors"]) == nil
    end
  end

  test "fetch a billing by id", %{user: user} do
    stripe_customer_id = "test_cus_JIdQjmJcjq"

    {:ok, billing} =
      Repo.fetch_by(Billing, %{
        stripe_customer_id: stripe_customer_id,
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => billing.id})
    assert {:ok, query_data} = result
    billing = get_in(query_data, [:data, "billing", "billing"])
    assert billing["stripe_customer_id"] == stripe_customer_id
  end

  test "fetch active billing organization", %{user: user} do
    stripe_customer_id = "test_cus_JIdQjmJcjq"
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    billing = get_in(query_data, [:data, "getOrganizationBilling", "billing"])
    assert billing["stripe_customer_id"] == stripe_customer_id
    assert billing["is_active"] == true
  end

  test "update payment method", %{user: user} do
    use_cassette "update_payment_method" do
      payment_method_id = "pm_1IgT1nEMShkCsLFnOd4GdL9I"

      result =
        auth_query_gql_by(:payment_method, user,
          variables: %{
            "StripePaymentMethodId" => payment_method_id
          }
        )

      assert {:ok, query_data} = result
      billing = get_in(query_data, [:data, "updatePaymentMethod", "billing"])

      assert billing["StripePaymentMethodId"] == "pm_1IgT1nEMShkCsLFnOd4GdL9I"
    end
  end

  test "fetch customer portal url", %{user: user} do
    use_cassette "customer_portal_link" do
      result = auth_query_gql_by(:customer_portal, user, variables: %{})
      assert {:ok, query_data} = result
      customer_portal = get_in(query_data, [:data, "customerPortal"])
      assert customer_portal["returnUrl"] == "https://test.glific.com/settings/billing"
      assert customer_portal["url"] == "https://billing.stripe.com/session/test_session_id"
    end
  end

  describe "role-conditional org resolution for billing" do
    test "admin passing another org's organization_id/id is pinned to their own org",
         %{user: admin_user} do
      other_organization =
        Fixtures.organization_fixture(%{shortcode: "other_org_billing_isolation"})

      # Billing.create_billing/1 attributes the row to the current *process* org context (not the
      # attrs), so pin the context to the foreign org explicitly rather than relying on
      # organization_fixture/1 having switched it as a side effect.
      Repo.put_organization_id(other_organization.organization_id)

      other_billing =
        Fixtures.billing_fixture(%{
          organization_id: other_organization.organization_id,
          name: "Foreign org billing",
          stripe_customer_id: "foreign_cus_isolation_id",
          email: "foreign@example.com"
        })

      # guard the precondition: the row genuinely belongs to the foreign org, so the assertions
      # below actually exercise a cross-org boundary rather than passing by coincidence
      assert other_billing.organization_id == other_organization.organization_id

      # organization_fixture/1 (called above) switches the process's org context to the
      # newly-created org, so this lookup must not rely on implicit organization_id scoping
      # from the process dictionary — it already filters explicitly by admin_user.organization_id.
      {:ok, own_billing} =
        Repo.fetch_by(
          Billing,
          %{name: "Billing name", organization_id: admin_user.organization_id},
          skip_organization_id: true
        )

      # get_organization_billing: passing another org's id must not leak that org's billing —
      # the resolver forces the caller's own org for a non-glific_admin role. The :gid scalar
      # only parses string-encoded values (see test/glific_web/schema/tag_test.exs's contactId
      # usage), so the id is passed via to_string/1.
      result =
        auth_query_gql_by(:list_by_org, admin_user,
          variables: %{"organizationId" => to_string(other_organization.organization_id)}
        )

      assert {:ok, query_data} = result
      billing = get_in(query_data, [:data, "getOrganizationBilling", "billing"])
      assert billing["stripe_customer_id"] == own_billing.stripe_customer_id
      refute billing["stripe_customer_id"] == other_billing.stripe_customer_id

      # update_billing: passing another org's billing id cannot reach it, because the fetch
      # is scoped to the caller's own organization_id for non-glific_admin roles.
      result =
        auth_query_gql_by(:update, admin_user,
          variables: %{
            "id" => other_billing.id,
            "input" => %{"email" => "hijacked@example.com"}
          }
        )

      assert {:ok, query_data} = result
      [error] = get_in(query_data, [:data, "updateBilling", "errors"])
      assert error["message"] == "Resource not found"

      {:ok, reloaded_other_billing} =
        Repo.fetch_by(Billing, %{id: other_billing.id}, skip_organization_id: true)

      assert reloaded_other_billing.email == "foreign@example.com"
    end

    test "glific_admin passing another org's id operates on that org",
         %{glific_admin: glific_admin_user, user: admin_user} do
      other_organization =
        Fixtures.organization_fixture(%{shortcode: "other_org_billing_operator"})

      # organization_fixture/1 (via Partners.create_organization/1) switches the process's
      # org context to the newly-created org, so the lookup below must not rely on implicit
      # organization_id scoping from the process dictionary — it already filters explicitly
      # by admin_user.organization_id, so skip the (now stale) implicit scope.
      {:ok, own_org_billing} =
        Repo.fetch_by(
          Billing,
          %{
            name: "Billing name",
            organization_id: admin_user.organization_id
          },
          skip_organization_id: true
        )

      # Re-home the seeded billing (stripe_customer_id is globally unique, so we move the
      # existing row rather than mint a second one) so glific_admin's update targets a
      # DIFFERENT org than its own, while still reusing the existing "update_billing"
      # cassette (matched by stripe_customer_id + request body) without any real Stripe call.
      {:ok, other_org_billing} =
        Billing.update_billing(own_org_billing, %{
          organization_id: other_organization.organization_id
        })

      assert other_org_billing.organization_id == other_organization.organization_id

      # Property under test: a glific_admin can reach and update a billing row that belongs to a
      # DIFFERENT org than its own (the operator cross-org path), AND the update does not re-home
      # the record. update_billing/3 strips :organization_id from the params for every role, so
      # the organization_id that AddOrganization auto-injects can no longer move the record to the
      # caller's org. The post-update assertion below verifies the row stays in the foreign org.
      use_cassette "update_billing" do
        result =
          auth_query_gql_by(:update, glific_admin_user,
            variables: %{
              "id" => other_org_billing.id,
              "input" => %{"email" => "testingbilling@gmail.com"}
            }
          )

        assert {:ok, query_data} = result
        assert get_in(query_data, [:data, "updateBilling", "errors"]) == nil
        email = get_in(query_data, [:data, "updateBilling", "billing", "email"])
        assert email == "testingbilling@gmail.com"
      end

      {:ok, reloaded_billing} =
        Repo.fetch_by(Billing, %{id: other_org_billing.id}, skip_organization_id: true)

      assert reloaded_billing.email == "testingbilling@gmail.com"

      # the record stays in the foreign org — it was NOT silently re-homed to the operator's org
      assert reloaded_billing.organization_id == other_organization.organization_id
    end

    test "own-org happy path still works when organization_id is explicitly the caller's own",
         %{user: admin_user} do
      result =
        auth_query_gql_by(:list_by_org, admin_user,
          variables: %{"organizationId" => to_string(admin_user.organization_id)}
        )

      assert {:ok, query_data} = result
      billing = get_in(query_data, [:data, "getOrganizationBilling", "billing"])
      assert billing["is_active"] == true
    end
  end
end
