defmodule Glific.Repo.Seeds.AddGoogleSlidesProvider do
  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:google_slides])

  def up(_repo, _opts) do
    add_google_slides_provider()
  end

  @spec add_google_slides_provider() :: any()
  defp add_google_slides_provider() do
    query = from(p in Provider, where: p.shortcode == "google_slides")

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Google Slides",
          shortcode: "google_slides",
          description: "Setup for using Google Slides for Certificates",
          group: nil,
          is_required: false,
          keys: %{},
          secrets: %{
            service_account: %{
              type: :string,
              label: "Goth Credentials",
              default: nil,
              view_only: false
            }
          }
        })
  end
end
