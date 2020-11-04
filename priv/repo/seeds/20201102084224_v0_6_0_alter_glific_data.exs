defmodule Glific.Repo.Seeds.AddGlificData_v0_6_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Repo,
    Settings.Language
  }

  def up(_repo) do
    add_languages()
  end

  defp add_languages() do
    if {:error, ["Elixir.Glific.Settings.Language", "Resource not found"]} ==
         Repo.fetch_by(Language, %{label: "Urdu"}, skip_organization_id: true) do
      Repo.insert!(
        %Language{
          label: "Urdu",
          label_locale: "اُردُو",
          locale: "ur"
        },
        skip_organization_id: true
      )
    end
  end
end
