defmodule GlificWeb.Schema.ContactTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    default_provider = Glific.Seeds.seed_providers()
    Glific.Seeds.seed_organizations(default_provider, lang)
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_tags/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contact_tags/delete.gql")

  test "create a contact tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    name = "Default Sender"
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: name})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    contact_tag = get_in(query_data, [:data, "createContactTag", "contact_tag"])

    assert contact_tag["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_tag["tag"]["id"] |> String.to_integer() == tag.id

    # try creating the same contact tag entry twice
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "createContactTag", "errors", Access.at(0), "message"])
    assert contact == "has already been taken"
  end

  test "delete a contact tag" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    name = "Default Sender"
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: name})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    contact_tag_id = get_in(query_data, [:data, "createContactTag", "contact_tag", "id"])

    result = query_gql_by(:delete, variables: %{"id" => contact_tag_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteContactTag", "errors"]) == nil

    # try to delete incorrect entry
    result = query_gql_by(:delete, variables: %{"id" => contact_tag_id})
    assert {:ok, query_data} = result

    contact = get_in(query_data, [:data, "deleteContactTag", "errors", Access.at(0), "message"])
    assert contact == "Resource not found"
  end
end
