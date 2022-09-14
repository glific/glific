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

  def up(_repo, _opts) do
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
            },
            app_id: %{
              type: :string,
              label: "App ID",
              default: "App ID",
              view_only: true
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
              app_name: "Glific42",
              app_id: "Glific42"
            },
            is_active: true
          })
    end)
  end

  defp add_providers() do
    add_dialogflow()

    add_bigquery()

    add_goth()

    add_google_cloud_storage()

    add_navana_tech()

    add_exotel()

    add_gupshup_enterprise()

    add_google_asr()
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
              label: "Dialogflow API Endpoint",
              default: "https://dialogflow.clients6.google.com/v2beta1/projects/",
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

  defp add_google_asr do
    query = from p in Provider, where: p.shortcode == "google_asr"

    # add google_asr
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "GoogleASR",
          shortcode: "google_asr",
          group: nil,
          is_required: false,
          keys: %{
            url: %{
              type: :string,
              label: "Google API Endpoint",
              default: "https://speech.googleapis.com/v1/speech:recognize",
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

  defp add_bigquery() do
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
              label: "BigQuery Url",
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

  defp add_navana_tech() do
    query = from p in Provider, where: p.shortcode == "navana_tech"

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Navana Tech",
          shortcode: "navana_tech",
          description: "Setup Navana tech APIs for NLP",
          group: nil,
          is_required: false,
          keys: %{
            url: %{
              type: :string,
              label: "Nanava Tech URL",
              default: "https://speechapi.southeastasia.cloudapp.azure.com",
              view_only: false
            }
          },
          secrets: %{
            token: %{
              type: :string,
              label: "JWT token",
              default: nil,
              view_only: false
            }
          }
        })
  end

  defp add_exotel() do
    query = from p in Provider, where: p.shortcode == "exotel"

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Exotel",
          shortcode: "exotel",
          description: "Implement Exotel callback to process optin and trigger flow",
          group: nil,
          is_required: false,
          keys: %{
            flow_id: %{
              type: :integer,
              label: "Glific Flow to trigger when a contact opts in",
              default: nil,
              view_only: false
            },
            direction: %{
              type: :string,
              label: "Is this an incoming or outbound-dial call",
              default: "incoming",
              view_only: false
            }
          },
          secrets: %{
            phone: %{
              type: :string,
              label: "Exotel Phone Number",
              default: nil,
              view_only: false
            }
          }
        })
  end

  defp add_gupshup_enterprise() do
    {:ok, gupshup_enterprise} = Repo.fetch_by(Provider, %{shortcode: "gupshup_enterprise"})

    Partners.active_organizations([])
    |> Enum.each(fn {org_id, _name} ->
      Glific.Repo.put_organization_id(org_id)

      query =
        from c in Credential,
          where: c.organization_id == ^org_id and c.provider_id == ^gupshup_enterprise.id

      if !Repo.exists?(query),
        do:
          Repo.insert!(%Credential{
            organization_id: org_id,
            provider_id: gupshup_enterprise.id,
            keys: %{
              url: "https://enterprise.smsgupshup.com/",
              api_end_point: "https://media.smsgupshup.com/GatewayAPI/rest",
              handler: "Glific.Providers.Gupshup.Enterprise.Message",
              worker: "Glific.Providers.Gupshup.Enterprise.Worker",
              bsp_limit: 40
            },
            secrets: %{
              hsm_user_id: "HSM account user id",
              hsm_password: "HSM account password",
              two_way_user_id: "Two-Way account user id",
              two_way_password: "Two-Way account password"
            },
            is_active: false
          })
    end)
  end
end
