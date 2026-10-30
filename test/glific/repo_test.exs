defmodule Glific.RepoTest do
  use Glific.DataCase, async: true
  use ExUnit.Case

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Partners,
    Partners.Organization,
    Repo,
    Settings,
    Settings.Language
  }

  describe "repo" do
    @valid_attrs %{
      label: "Faker English",
      label_locale: "Faker English",
      locale: "faker_en",
      is_active: true
    }

    @valid_hindi_attrs %{
      label: "Faker Hindi (India)",
      label_locale: "Faker हिन्दी",
      locale: "faker_hi",
      is_active: true
    }

    def language_fixture(attrs \\ @valid_attrs) do
      {:ok, language} =
        attrs
        |> Enum.into(attrs)
        |> Settings.language_upsert()

      language
    end

    test "fetch returns the right language" do
      en = language_fixture()
      hi = language_fixture(@valid_hindi_attrs)

      assert {:ok, hi} == Repo.fetch(Language, hi.id)
      assert {:ok, en} == Repo.fetch(Language, en.id)
      assert :error == elem(Repo.fetch(Language, 123), 0)
    end

    test "skip_permission should raise error when there is no current user" do
      Process.delete({Repo, :user})

      assert_raise RuntimeError, fn ->
        Repo.skip_permission?()
      end
    end

    test "prepare_query should raise error when user is not admin", attrs do
      query = get_query(attrs)

      assert_raise RuntimeError, fn ->
        Repo.prepare_query("hello", query, [])
      end
    end

    test "opts_with_nil should return query", attrs do
      query = get_query(attrs)

      assert query == Repo.opts_with_nil(query, [])
    end

    test "make_like should return query", attrs do
      query = get_query(attrs)

      assert query == Repo.make_like(query, :test, "")
      assert query == Repo.make_like(query, :test, nil)
    end

    test "add_opts should return query when opts_with_fn is nil", attrs do
      query = get_query(attrs)

      assert query == Repo.add_opts(query, nil, [])
    end

    defp get_query(attrs) do
      organization = Partners.organization(attrs.organization_id)

      Organization
      |> where([o], o.shortcode == ^organization.shortcode)
      |> select([o], o.id)
    end

    test "fetch_by returns the right language" do
      en = language_fixture()
      hi = language_fixture(@valid_hindi_attrs)

      assert {:ok, hi} ==
               Repo.fetch_by(Language, %{label: "Faker Hindi (India)"})

      assert {:ok, en} ==
               Repo.fetch_by(Language, %{locale: "faker_en"})

      assert :error ==
               elem(
                 Repo.fetch_by(Language, %{locale: "does not exist"}),
                 0
               )
    end
  end

  describe "audit versions" do
    defp update_contact_name(contact, name) do
      contact
      |> Contact.changeset(%{name: name})
      |> Repo.update(skip_organization_id: true)
    end

    defp updated_version(contact) do
      contact
      |> Repo.history(skip_organization_id: true)
      |> Enum.find(&(&1.action == :updated))
    end

    test "background write without ExAudit.track stamps the process organization",
         %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture()

      Task.async(fn ->
        Repo.put_organization_id(organization_id)
        {:ok, _} = update_contact_name(contact, "Background update")
      end)
      |> Task.await()

      version = updated_version(contact)
      assert version.organization_id == organization_id
      assert is_nil(version.user_id)
    end

    test "tracked write keeps both user_id and organization_id",
         %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture()
      user = Fixtures.user_fixture()

      Task.async(fn ->
        Repo.put_organization_id(organization_id)
        ExAudit.track(user_id: user.id, organization_id: user.organization_id)
        {:ok, _} = update_contact_name(contact, "Tracked update")
      end)
      |> Task.await()

      version = updated_version(contact)
      assert version.organization_id == organization_id
      assert version.user_id == user.id
    end

    test "process without an organization does not override ExAudit.track data",
         %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture()
      user = Fixtures.user_fixture()

      Task.async(fn ->
        ExAudit.track(user_id: user.id, organization_id: organization_id)
        {:ok, _} = update_contact_name(contact, "No process organization")
      end)
      |> Task.await()

      version = updated_version(contact)
      assert version.organization_id == organization_id
      assert version.user_id == user.id
    end
  end
end
