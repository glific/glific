defmodule GlificWeb.Schema.WAManagedPhoneTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Faker.Phone

  alias Glific.{Fixtures, Partners}

  load_gql(:count, GlificWeb.Schema, "assets/gql/wa_managed_phones/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/wa_managed_phones/list.gql")
  load_gql(:screen, GlificWeb.Schema, "assets/gql/wa_managed_phones/screen.gql")
  load_gql(:reconnect, GlificWeb.Schema, "assets/gql/wa_managed_phones/reconnect.gql")
  load_gql(:sync_statuses, GlificWeb.Schema, "assets/gql/wa_managed_phones/sync_statuses.gql")

  defp maytapi_credential(organization_id) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{"product_id" => "prod-123", "token" => "tok-123"},
      is_active: true
    })
  end

  test "wa_managed_phones field returns list of wa_managed_phones", %{manager: user} = attrs do
    seed_wa_managed_phone = Fixtures.wa_managed_phone_fixture(attrs)
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    wa_managed_phones = get_in(query_data, [:data, "wa_managed_phones"])
    assert length(wa_managed_phones) > 0
    [wa_managed_phone | _] = wa_managed_phones
    assert wa_managed_phone["label"] == seed_wa_managed_phone.label
    assert wa_managed_phone["phone"] == seed_wa_managed_phone.phone
    assert wa_managed_phone["status"] == seed_wa_managed_phone.status
  end

  test "wa_managed_phones field returns list of wa_managed_phones in desc order",
       %{manager: user} = attrs do
    _seed_wa_managed_phone_1 = Fixtures.wa_managed_phone_fixture(attrs)
    :timer.sleep(1000)

    valid_attrs_2 =
      Map.merge(attrs, %{phone: Phone.EnUs.phone()})

    seed_wa_managed_phone_2 = Fixtures.wa_managed_phone_fixture(valid_attrs_2)

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result
    wa_managed_phones = get_in(query_data, [:data, "wa_managed_phones"])
    assert length(wa_managed_phones) > 0
    [wa_managed_phone | _] = wa_managed_phones
    assert wa_managed_phone["phone"] == seed_wa_managed_phone_2.phone
  end

  test "wa_managed_phones field returns list of wa_managed_phones in various filters",
       %{manager: user} = attrs do
    seed_wa_managed_phone_1 = Fixtures.wa_managed_phone_fixture(attrs)

    valid_attrs_2 =
      Map.merge(attrs, %{phone: Phone.EnUs.phone()})

    _seed_wa_managed_phone_2 = Fixtures.wa_managed_phone_fixture(valid_attrs_2)

    result =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"phone" => seed_wa_managed_phone_1.phone}}
      )

    assert {:ok, query_data} = result
    wa_managed_phones = get_in(query_data, [:data, "wa_managed_phones"])
    assert length(wa_managed_phones) > 0
    [wa_managed_phone | _] = wa_managed_phones
    assert get_in(wa_managed_phone, ["phone"]) == seed_wa_managed_phone_1.phone

    result =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"label" => seed_wa_managed_phone_1.label}}
      )

    assert {:ok, query_data} = result
    wa_managed_phones = get_in(query_data, [:data, "wa_managed_phones"])
    assert length(wa_managed_phones) > 0
    [wa_managed_phone | _] = wa_managed_phones
    assert get_in(wa_managed_phone, ["label"]) == seed_wa_managed_phone_1.label
  end

  test "wa_managed_phones field obeys limit and offset", %{manager: user} = attrs do
    _seed_wa_managed_phone_1 = Fixtures.wa_managed_phone_fixture(attrs)

    valid_attrs_2 =
      Map.merge(attrs, %{phone: Phone.EnUs.phone()})

    _seed_wa_managed_phone_2 = Fixtures.wa_managed_phone_fixture(valid_attrs_2)

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "wa_managed_phones"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 1}})

    assert {:ok, query_data} = result

    wa_managed_phones = get_in(query_data, [:data, "wa_managed_phones"])
    assert length(wa_managed_phones) == 1
  end

  test "count returns the number of wa_managed_phones", %{manager: user} = attrs do
    _seed_wa_managed_phone_1 = Fixtures.wa_managed_phone_fixture(attrs)
    valid_attrs_2 = Map.merge(attrs, %{phone: Phone.EnUs.phone()})
    seed_wa_managed_phone_2 = Fixtures.wa_managed_phone_fixture(valid_attrs_2)

    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countWaManagedPhones"]) == 2

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"phone" => seed_wa_managed_phone_2.phone}}
      )

    assert get_in(query_data, [:data, "countWaManagedPhones"]) == 1
  end

  test "whatsapp_phone_screen returns the QR payload for an admin",
       %{glific_admin: user} = attrs do
    phone = Fixtures.wa_managed_phone_fixture(attrs)
    maytapi_credential(user.organization_id)

    # Maytapi returns the screen as raw PNG bytes
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{status: 200, body: <<137, 80, 78, 71, 13, 10, 26, 10>>}
    end)

    result = auth_query_gql_by(:screen, user, variables: %{"wa_managed_phone_id" => phone.id})
    assert {:ok, query_data} = result

    code = get_in(query_data, [:data, "whatsapp_phone_screen", "wa_phone_screen", "code"])
    assert String.starts_with?(code, "data:image/png;base64,")
  end

  test "whatsapp_phone_screen is rejected for a non-admin", %{manager: user} = attrs do
    phone = Fixtures.wa_managed_phone_fixture(attrs)

    result = auth_query_gql_by(:screen, user, variables: %{"wa_managed_phone_id" => phone.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:errors]) != nil
  end

  test "reconnect_wa_managed_phone logs the phone out for an admin",
       %{glific_admin: user} = attrs do
    phone = Fixtures.wa_managed_phone_fixture(attrs)
    maytapi_credential(user.organization_id)

    Tesla.Mock.mock(fn _env -> %Tesla.Env{status: 200, body: ~s({"success":true})} end)

    result = auth_query_gql_by(:reconnect, user, variables: %{"wa_managed_phone_id" => phone.id})
    assert {:ok, query_data} = result

    id = get_in(query_data, [:data, "reconnect_wa_managed_phone", "wa_managed_phone", "id"])
    assert String.to_integer(id) == phone.id
  end

  test "reconnect_wa_managed_phone is rejected for a non-admin", %{staff: user} = attrs do
    phone = Fixtures.wa_managed_phone_fixture(attrs)

    result = auth_query_gql_by(:reconnect, user, variables: %{"wa_managed_phone_id" => phone.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:errors]) != nil
  end

  test "sync_wa_managed_phone_statuses reconciles statuses for a manager",
       %{manager: user} = attrs do
    Fixtures.wa_managed_phone_fixture(attrs)
    maytapi_credential(user.organization_id)

    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body: ~s([{"id":242,"number":"9829627508","status":"active","type":"whatsapp"}])
      }
    end)

    result = auth_query_gql_by(:sync_statuses, user)
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "sync_wa_managed_phone_statuses", "message"])
    assert message =~ "refreshed"
  end

  test "sync_wa_managed_phone_statuses is rejected for staff", %{staff: user} do
    result = auth_query_gql_by(:sync_statuses, user)
    assert {:ok, query_data} = result
    assert get_in(query_data, [:errors]) != nil
  end
end
