defmodule Glific.Repo.Seeds.AddGlificData_v0_4_1 do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners,
    Partners.Credential,
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

    Partners.active_organizations()
    |> Enum.each(fn {org_id, _name} ->
      Repo.insert!(%Credential{
        organization_id: org_id,
        provider_id: gupshup.id,
        keys: %{
          url: "https://gupshup.io/",
          api_end_point: "https://api.gupshup.io/sm/api/v1",
          handler: "Glific.Providers.Gupshup.Message",
          worker: "Glific.Providers.Gupshup.Worker"
        },
        secrets: %{
          api_key: "Please enter your key here",
          app_name: "Please enter your App Name here"
        }
      })

      Repo.insert!(%Credential{
        organization_id: org_id,
        provider_id: glifproxy.id,
        keys: %{
          url: "https://glific.io/",
          api_end_point: "We need to figure out how to get this dynamically, maybe in services?",
          handler: "Glific.Providers.Gupshup.Message",
          worker: "Glific.Providers.Glifproxy.Worker"
        },
        secrets: %{}
      })
    end)
  end
end
