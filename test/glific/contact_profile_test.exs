defmodule Glific.ContactProfilesTest do
  use Glific.DataCase, async: true
  import Glific.Fixtures

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Settings.Language
  }

  @valid_attrs %{
    name: "some name",
    optin_time: ~U[2010-04-17 14:00:00Z],
    optin_status: false,
    optout_time: nil,
    phone: "some phone",
    status: :valid,
    bsp_status: :hsm,
    language_id: 1,
    fields: %{}
  }

  test "create_contact/1 creates a contact and profile",
       %{organization_id: _organization_id} = attrs do
    {:ok, language} = Repo.fetch_by(Language, %{locale: "hi"})

    profile1 = profile_fixture(%{"name" => "john", "type" => "admin"})
    profile2 = profile_fixture(%{"name" => "max", "type" => "staff"})

    attrs =
      attrs
      |> Map.merge(@valid_attrs)
      |> Map.merge(%{language_id: language.id})
      |> Map.merge(%{active_profile_id: profile2.id})

    assert {:ok, %Contact{} = contact} = Contacts.create_contact(attrs)
    assert profile2.id == contact.active_profile_id
    refute profile1.id == contact.active_profile_id

    contact = Repo.get_by!(Contact, id: contact.id) |> Repo.preload(:active_profile)
    assert contact.active_profile.name == profile2.name
  end
end
