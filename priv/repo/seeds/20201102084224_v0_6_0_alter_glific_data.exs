defmodule Glific.Repo.Seeds.AddGlificData_v0_6_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  @global_schema Application.fetch_env!(:glific, :global_schema)

  alias Glific.{
    Repo,
    Settings.Language
  }

  def up(_repo) do
    add_languages()
  end

  defp add_languages() do
    if {:error, ["Elixir.Glific.Settings.Language", "Resource not found"]} ==
         Repo.fetch_by(Language, %{label: "Urdu"}, prefix: @global_schema) do
      Repo.insert!(
        %Language{
          label: "Urdu",
          label_locale: "اُردُو",
          locale: "ur"
        },
        prefix: @global_schema
      )
    end
  end
end
