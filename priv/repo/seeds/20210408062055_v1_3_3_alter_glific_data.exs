defmodule Glific.Repo.Seeds.V133AlterGlificData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Settings.Language,
    Repo
  }

  def up(_repo) do
    update_language_localized()
  end

  defp update_language_localized() do
    languages = Repo.all(Language, skip_organization_id: true)
IO.inspect(languages)
    languages
    |> Enum.each(fn language ->
      if Enum.member?(["en_US", "hi"], language.locale) do
        Repo.update!(Ecto.Changeset.change(language, %{localized: true}))
      end
    end)
  end
end
