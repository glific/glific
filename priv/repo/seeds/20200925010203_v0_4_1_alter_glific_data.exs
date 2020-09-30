defmodule Glific.Repo.Seeds.AddGlificData_v0_4_1 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Repo
  }

  def up(_repo) do
    # add pseudo credentials for gupshup and glifproxy
    {:ok, gupshup} = Repo.fetch_by(Provider, %{name: "Gupshup"})
    {:ok, glifproxy} = Repo.fetch_by(Provider, %{name: "Glifproxy"})

    # update providers gupshup and glifproxy with values for:
    # shortcode, group, is_required, keys and secrets
    Repo.update!(
      Ecto.Changeset.change(
        gupshup,
        %{
          shortcode: "gupshup",
          group: "bsp",
          is_required: true,
          keys: %{
            url: %{
              type: :string,
              label: "BSP Home Page",
              default: "https://gupshup.io/",
              view_only: true
            },
            api_end_point: %{
              type: :string,
              label: "API End Point",
              default: "https://api.gupshup.io/sm/api/v1",
              view_only: false
            },
            handler: %{
              type: :string,
              label: "Inbound Message Handler",
              default: "Glific.Providers.Gupshup.Message",
              view_only: true
            },
            worker: %{
              type: :string,
              label: "Outbound Message Worker",
              default: "Glific.Providers.Gupshup.Worker",
              view_only: true
            }
          },
          secrets: %{
            api_key: %{
              type: :string,
              label: "API Key",
              default: nil,
              view_only: false
            },
            app_name: %{
              type: :string,
              label: "App Name",
              default: nil,
              view_only: false
            }
          }
        }
      )
    )

    Repo.update!(
      Ecto.Changeset.change(
        glifproxy,
        %{
          shortcode: "glifproxy",
          group: "bsp",
          is_required: true,
          keys: %{
            url: %{
              type: :string,
              label: "BSP Home Page",
              default: "https://glific.io/",
              view_only: true
            },
            api_end_point: %{
              type: :string,
              label: "API End Point",
              default: "https://glific.test:4000/",
              view_only: false
            },
            handler: %{
              type: :string,
              label: "Inbound Message Handler",
              default: "Glific.Providers.Gupshup.Message",
              view_only: true
            },
            worker: %{
              type: :string,
              label: "Outbound Message Worker",
              default: "Glific.Providers.Glifproxy.Worker",
              view_only: true
            }
          },
          secrets: %{}
        }
      )
    )

  end
end
