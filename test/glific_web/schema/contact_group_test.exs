defmodule GlificWeb.Schema.ContactGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Groups.Group,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_groups()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_groups/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contact_groups/delete.gql")

  test "create a contact group and test possible scenarios and errors" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    contact_group = get_in(query_data, [:data, "createContactGroup", "contact_group"])

    assert contact_group["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_group["group"]["id"] |> String.to_integer() == group.id

    # try creating the same contact group entry twice
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "createContactGroup", "errors", Access.at(0), "message"])
    assert contact == "has already been taken"
  end

  test "delete a contact group" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "group_id" => group.id}}
      )

    contact_group_id = get_in(query_data, [:data, "createContactGroup", "contact_group", "id"])

    result = query_gql_by(:delete, variables: %{"id" => contact_group_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteContactGroup", "errors"]) == nil

    # try to delete incorrect entry
    result = query_gql_by(:delete, variables: %{"id" => contact_group_id})
    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "deleteContactGroup", "errors", Access.at(0), "message"])
    assert contact == "Resource not found"
  end
end
