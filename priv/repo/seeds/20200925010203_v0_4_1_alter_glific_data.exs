defmodule Glific.Repo.Seeds.AddGlificData_v0_4_1 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  import Ecto.Query

  alias Glific.{
    Partners,
    Partners.Credential,
    Partners.Provider,
    Repo
  }

  def up(_repo) do
    update_exisiting_providers()

    add_providers()
  end

  defp update_exisiting_providers() do
    # add pseudo credentials for gupshup and glifproxy
    {:ok, gupshup} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})
    {:ok, glifproxy} = Repo.fetch_by(Provider, %{shortcode: "glifproxy"})

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

    add_credentials(gupshup, glifproxy)
  end

  defp add_credentials(gupshup, glifproxy) do
    Partners.active_organizations()
    |> Enum.each(fn {org_id, _name} ->
      query =
        from c in Credential,
          where: c.organization_id == ^org_id and c.provider_id == ^gupshup.id

      if !Repo.exists?(query),
        do:
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
              api_key: "This is top secret",
              app_name: "Glific42"
            },
            is_active: true
          })

      query =
        from c in Credential,
          where: c.organization_id == ^org_id and c.provider_id == ^glifproxy.id

      if !Repo.exists?(query),
        do:
          Repo.insert!(%Credential{
            organization_id: org_id,
            provider_id: glifproxy.id,
            keys: %{
              url: "https://glific.io/",
              api_end_point:
                "We need to figure out how to get this dynamically, maybe in services?",
              handler: "Glific.Providers.Gupshup.Message",
              worker: "Glific.Providers.Glifproxy.Worker"
            },
            secrets: %{},
            is_active: true
          })
    end)
  end

  defp add_providers() do
    add_dialogflow()

    add_chatbase()

    add_goth()

    add_google_cloud_storage()
  end

  defp add_dialogflow do
    query = from p in Provider, where: p.shortcode == "dialogflow"

    # add dialogflow
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Dialogflow",
          shortcode: "dialogflow",
          group: nil,
          is_required: false,
          keys: %{
            url: %{
              type: :string,
              label: "Dialogdlow Home Page",
              default: "https://dialogflow.cloud.google.com/",
              view_only: true
            }
          },
          secrets: %{
            project_id: %{
              type: :string,
              label: "Project ID",
              default: nil,
              view_only: false
            },
            project_email: %{
              type: :string,
              label: "Project Email",
              default: nil,
              view_only: false
            }
          }
        })

  end

  defp add_goth do
    # add goth (since we'll be using other google services also)
    query = from p in Provider, where: p.shortcode == "goth"

    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "GOTH",
          shortcode: "goth",
          group: nil,
          is_required: false,
          keys: %{},
          secrets: %{
            json: %{
              type: :string,
              label: "JSON Credentials ",
              default: nil,
              view_only: false
            }
          }
        })
  end

  defp add_chatbase() do
    # add chatbase
    query = from p in Provider, where: p.shortcode == "chatbase"

    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Chatbase",
          shortcode: "chatbase",
          group: nil,
          is_required: false,
          keys: %{},
          secrets: %{
            api_key: %{
              type: :string,
              label: "API Key",
              default: nil,
              view_only: false
            }
          }
        })
  end

  defp add_google_cloud_storage() do
    query = from p in Provider, where: p.shortcode == "google_cloud_storage"

    # add google cloud storage (gcs)
    if !Repo.exists?(query),
      do:
    Repo.insert!(%Provider{
          name: "Google Cloud Storage",
          shortcode: "google_cloud_storage",
          group: nil,
          is_required: false,
          keys: %{},
          secrets: %{
            email: %{
              type: :string,
              label: "Email",
              default: nil,
              view_only: false
            }
          }
                 })
  end
end
