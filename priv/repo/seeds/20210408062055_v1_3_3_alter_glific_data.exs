defmodule Glific.Repo.Seeds.V133AlterGlificData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Settings.Language,
    Repo
  }

  def up(_repo) do
    update_language_localized()
    update_locale()
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
end
