Code.require_file("../../../.credo/checks/contact_phone_lookup.ex", __DIR__)

defmodule GlificCredo.Checks.ContactPhoneLookupTest do
  use ExUnit.Case, async: true

  alias GlificCredo.Checks.ContactPhoneLookup

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(body, filename \\ "lib/glific/sample.ex") do
    """
    defmodule Glific.Sample do
      def run(phone, name) do
        #{body}
      end
    end
    """
    |> Credo.SourceFile.parse(filename)
    |> ContactPhoneLookup.run([])
  end

  test "flags Repo lookups on Contact keyed on phone" do
    assert [_] = issues("Repo.get_by(Contact, %{phone: phone})")
    assert [_] = issues("Glific.Repo.get_by!(Contact, phone: phone)")
    assert [_] = issues("RepoReplica.fetch_by(Glific.Contacts.Contact, %{phone: phone})")
  end

  test "flags Repo lookups with options and piped from Contact" do
    assert [_] = issues("Repo.fetch_by(Contact, %{phone: phone}, skip_organization_id: true)")
    assert [_] = issues("Contact |> Repo.get_by(%{phone: phone})")
    assert [_] = issues("Contact |> Repo.get_by!(phone: phone)")

    assert [_] =
             issues(
               "Contact |> RepoReplica.fetch_by(%{phone: phone}, skip_organization_id: true)"
             )
  end

  test "is best-effort: clauses held in a variable are not flagged" do
    assert [] = issues("clauses = %{phone: phone}\n    Repo.get_by(Contact, clauses)")
    assert [] = issues("Contact |> Repo.get_by(%{id: phone})")
  end

  test "flags from/2 queries on Contact that compare phone" do
    assert [_] = issues("from(c in Contact, where: c.phone == ^phone)")
    assert [_] = issues("from(c in Contact, where: ^phone == c.phone, select: c.id)")
    assert [_] = issues("from(c in Contact, where: c.name == ^name or c.phone == ^phone)")
    assert [_] = issues("from(c in Contact, or_where: c.phone == ^phone)")
    assert [_] = issues("from(c in Contact, where: [phone: ^phone])")
  end

  test "flags where/3 on Contact, piped or direct" do
    assert [_] = issues("Contact |> where([c], c.phone == ^phone) |> Repo.one()")
    assert [_] = issues("Contact |> select([c], c.id) |> where([c], c.phone == ^phone)")
    assert [_] = issues("where(Contact, [c], c.phone == ^phone)")
  end

  test "ignores other lookups and other schemas" do
    assert [] = issues("Repo.get_by(Contact, %{id: phone})")
    assert [] = issues("Repo.get_by(TrialAccount, %{phone: phone})")
    assert [] = issues("from(t in TrialAccount, where: t.phone == ^phone)")
    assert [] = issues("from(c in Contact, where: c.name == ^name)")
    assert [] = issues("from(c in Contact, where: is_nil(c.phone))")
    assert [] = issues("Contact |> where([c], c.name == ^name)")
    assert [] = issues("from(c in Contact, join: t in Tag, on: t.phone == ^phone)")
  end

  test "exempts Glific.Contacts and test files" do
    contacts_module = """
    defmodule Glific.Contacts do
      def run(phone), do: Repo.get_by(Contact, %{phone: phone})
    end
    """

    assert [] =
             contacts_module
             |> Credo.SourceFile.parse("lib/glific/contacts.ex")
             |> ContactPhoneLookup.run([])

    assert [] = issues("Repo.get_by(Contact, %{phone: phone})", "test/glific/sample_test.exs")
  end
end
