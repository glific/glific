defmodule GlificWeb.Schema.ContactTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Repo,
    Seeds.SeedsDev,
    Tags.Tag
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_tag/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contact_tag/delete.gql")

  test "create a contact tag and test possible scenarios and errors", %{user: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    contact_tag = get_in(query_data, [:data, "createContactTag", "contact_tag"])

    assert contact_tag["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_tag["tag"]["id"] |> String.to_integer() == tag.id

    # try creating the same contact tag entry twice
    # upserts come into play here and we dont return an error
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    contact_tag = get_in(query_data, [:data, "createContactTag", "contact_tag"])
    assert get_in(contact_tag, ["contact", "id"]) |> String.to_integer() == contact.id
    assert get_in(contact_tag, ["tag", "id"]) |> String.to_integer() == tag.id
  end

  test "delete a contact tag", %{user: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

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
