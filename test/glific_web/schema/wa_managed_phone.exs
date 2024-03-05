defmodule GlificWeb.Schema.WAManagedPhoneTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Faker.Phone

  alias Glific.Fixtures

  load_gql(:count, GlificWeb.Schema, "assets/gql/wa_managed_phones/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/wa_managed_phones/list.gql")

  test "wa_managed_phones field returns list of wa_managed_phones", %{manager: user} = attrs do
    seed_wa_managed_phone = Fixtures.wa_managed_phone_fixture(attrs)
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    wa_managed_phones = get_in(query_data, [:data, "wa_managed_phones"])
    assert length(wa_managed_phones) > 0
    [wa_managed_phone | _] = wa_managed_phones
    assert wa_managed_phone["label"] == seed_wa_managed_phone.label
    assert wa_managed_phone["phone"] == seed_wa_managed_phone.phone
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
end
