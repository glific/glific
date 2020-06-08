defmodule GlificWeb.Schema.Query.ContactTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    :ok
  end

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/contact_tags/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_tags/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/contact_tags/delete.gql")

  test "contact tag id returns one contact tag or nil" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    name = "Default Sender"
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: name})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    contact_tag_id = get_in(query_data, [:data, "createContactTag", "contact_tag", "id"])

    result = query_gql_by(:by_id, variables: %{"id" => contact_tag_id})
    assert {:ok, query_data} = result

    contact_id = get_in(query_data, [:data, "contactTag", "contact_tag", "id"])
    assert contact_id == contact_id
  end

  test "create a contact tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    name = "Default Sender"
    {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: name})

    IO.inspect(tag.id)
    IO.inspect(contact.id)

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"contact_id" => contact.id, "tag_id" => tag.id}}
      )

    IO.inspect(result)

    assert {:ok, query_data} = result

    contact_tag = get_in(query_data, [:data, "createContactTag", "contact_tag"])

    IO.inspect(contact_tag)

    assert contact_tag["contact"]["id"] |> String.to_integer() == contact.id
    assert contact_tag["tag"]["id"] |> String.to_integer() == tag.id
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
  end
end
