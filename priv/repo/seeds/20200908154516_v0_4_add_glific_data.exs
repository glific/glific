defmodule Glific.Repo.Seeds.V04AddGlificData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Repo,
    Settings,
    Settings.Language
  }

  @now DateTime.utc_now() |> DateTime.truncate(:second)

  def up(_repo) do
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    queries = [
      "UPDATE organizations SET provider_limit = 60, active_language_ids = '{#{en_us.id}}';",
      "UPDATE providers SET handler = 'Glific.Providers.Gupshup.Message', worker = 'Glific.Providers.Gupshup.Worker'"
    ]

    Enum.each(
      queries,
      &Repo.query(&1)
    )

    # add glifproxy as a channel also
    Repo.insert!(%Provider{
      name: "Glifproxy",
      url: "https://glific.io/",
      api_end_point: "http://glific.test:4000",
      handler: "Glific.Providers.Gupshup.Message",
      worker: "Glific.Providers.Glifproxy.Worker"
    })

    add_languages()
  end

  defp add_languages() do
    languages = [
      %{
        label: "Kannada",
        label_locale: "ಕನ್ನಡ",
        locale: "kn"
      },
      %{
        label: "Malayalam",
        label_locale: "മലയാളം",
        locale: "ml"
      },
      %{
        label: "Telugu",
        label_locale: "తెలుగు",
        locale: "te"
      },
      %{
        label: "Odia",
        label_locale: "ଓଡ଼ିଆ",
        locale: "or"
      },
      %{
        label: "Assamese",
        label_locale: "অসমীয়া",
        locale: "as"
      },
      %{
        label: "Gujarati",
        label_locale: "ગુજરાતી",
        locale: "gu"
      },
      %{
        label: "Bengali",
        label_locale: "বাংলা",
        locale: "bn"
      },
      %{
        label: "Punjabi",
        label_locale: "ਪੰਜਾਬੀ",
        locale: "pa"
      },
      %{
        label: "Marathi",
        label_locale: "मराठी",
        locale: "mr"
      }
    ]

    languages =
      Enum.map(
        languages,
        fn language ->
          language
          |> Map.put(:inserted_at, @now)
          |> Map.put(:updated_at, @now)
        end
      )

    # seed languages
    Repo.insert_all(Language, languages)
  end
end
