defmodule Glific.Repo.Seeds.V04AddGlificData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners,
    Partners.Organization,
    Repo,
    Repo.Seeds.AddGlificOrganizationData,
    Settings
  }

  def up(_repo) do
    [provider | _] = Partners.list_providers()
    languages = Settings.list_languages()

    organizations(provider, languages)
    |> Enum.each(fn organization ->
      AddGlificOrganizationData.seed_data(organization, languages)
    end)
  end

  def organizations(provider, languages) do
    [en_us | _] = languages

    out_of_office_default_data = %{
      enabled: false,
      enabled_days: [
        %{enabled: false, id: 1},
        %{enabled: false, id: 2},
        %{enabled: false, id: 3},
        %{enabled: false, id: 4},
        %{enabled: false, id: 5},
        %{enabled: false, id: 6},
        %{enabled: false, id: 7}
      ]
    }

    org2 =
      Repo.insert!(%Organization{
        name: "Glific2",
        shortcode: "glific2",
        email: "ADMIN@REPLACE_ME2.NOW",
        provider_id: provider.id,
        provider_key: "ADD_PROVIDER_API_KEY2",
        provider_phone: "9178348111142",
        default_language_id: en_us.id,
        out_of_office: out_of_office_default_data
      })

    org3 =
      Repo.insert!(%Organization{
        name: "Glific3",
        shortcode: "glific3",
        email: "ADMIN@REPLACE_ME3.NOW",
        provider_id: provider.id,
        provider_key: "ADD_PROVIDER_API_KEY3",
        provider_phone: "9178348111143",
        default_language_id: en_us.id,
        out_of_office: out_of_office_default_data
      })

    [org2, org3]
  end
end
