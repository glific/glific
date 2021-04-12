defmodule Glific.Repo.Seeds.V133AlterGlificData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners,
    Partners.Organization,
    Repo,
    Settings,
    Settings.Language,
    Users,
    Users.User
  }

  def up(_repo) do
    update_language_localized()
    update_locale()
    update_user_default_language()
  end

  defp update_language_localized() do
    Repo.all(Language, skip_organization_id: true)
    |> Enum.each(fn language ->
      if Enum.member?(["en_US", "hi"], language.locale) do
        Repo.update!(Ecto.Changeset.change(language, %{localized: true}))
      end
    end)
  end

  defp update_locale() do
    en = Repo.get_by(Language, %{locale: "en_US"})
    Settings.update_language(en, %{locale: "en"})
  end

  defp update_user_default_language() do
    Repo.all(Organization, skip_organization_id: true)
    |> Enum.each(fn organization -> update_users(organization) end)
  end

  defp update_users(org) do
    Users.list_users(%{organization_id: org.id})
    |> Enum.each(fn user -> Users.update_user(user, %{language_id: org.default_language_id}) end)
  end
end
