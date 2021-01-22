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
    # add pseudo credentials for gupshup
    {:ok, gupshup} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

    # update providers gupshup with values for:
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

    add_credentials(gupshup)
  end

  defp add_credentials(gupshup) do
    Partners.active_organizations([])
    |> Enum.each(fn {org_id, _name} ->
      Glific.Repo.put_organization_id(org_id)

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
              worker: "Glific.Providers.Gupshup.Worker",
              bsp_limit: 40
            },
            secrets: %{
              api_key: "This is top secret",
              app_name: "Glific42"
            },
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
            },
            service_account: %{
              type: :string,
              label: "Goth Credentials ",
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
          keys: %{
            url: %{
              type: :string,
              label: "Goth Url",
              default: "https://dialogflow.clients6.google.com",
              view_only: true
            }
          },
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

    # add bigquery
    query = from p in Provider, where: p.shortcode == "bigquery"

    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "BigQuery",
          shortcode: "bigquery",
          group: nil,
          is_required: false,
          keys: %{
            url: %{
              type: :string,
              label: "Bigquery Url",
              default: "https://www.googleapis.com/auth/cloud-platform",
              view_only: true
            }
          },
          secrets: %{
            service_account: %{
              type: :string,
              label: "Goth Credentials ",
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
            },
            bucket: %{
              type: :string,
              label: "Bucket",
              default: nil,
              view_only: false
            },
            service_account: %{
              type: :string,
              label: "Goth Credentials ",
              default: nil,
              view_only: false
            }
          }
        })
  end
end
