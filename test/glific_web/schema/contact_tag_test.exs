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

  test "create a contact tag and test possible scenarios and errors", %{staff: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})
    name = "Glific Admin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    contact_tag = get_in(query_data, [:data, "createContactTag", "contact_tag"])

    assert contact_tag["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_tag["tag"]["id"] |> String.to_integer() == tag.id

    # try creating the same contact tag entry twice
    # upserts come into play here and we dont return an error
    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    contact_tag = get_in(query_data, [:data, "createContactTag", "contact_tag"])
    assert get_in(contact_tag, ["contact", "id"]) |> String.to_integer() == contact.id
    assert get_in(contact_tag, ["tag", "id"]) |> String.to_integer() == tag.id
  end
end
