# Script for populating the database with developer credentials. You can run it as:
#
#     mix run priv/repo/seeds_credentials.exs
#

defmodule Glific.Seeds.Credentials do
  import Ecto.Query

  alias Glific.{
    Partners.Credential,
    Partners.Provider,
    Repo
  }

  def get_secrets,
    do: Application.fetch_env!(:glific, :secrets)

  def update_gupshup_credentials(nil = _gupshup, _organization_id), do: nil

  def update_gupshup_credentials(gupshup, organization_id) do
    secrets = %{
      api_key: Keyword.get(gupshup, :api_key),
      app_name: Keyword.get(gupshup, :app_name)
    }

    query =
      from c in Credential,
        join: p in Provider,
        on: c.provider_id == p.id,
        where: p.shortcode == "gupshup" and c.organization_id == ^organization_id

    Repo.update_all(query, set: [secrets: secrets])
  end

  def insert_dialogflow_credentials(nil = _dflow, _organization_id), do: nil

  def insert_dialogflow_credentials(dflow, organization_id) do
    {:ok, dialogflow} = Repo.fetch_by(Provider, %{shortcode: "dialogflow"})

    Repo.insert!(%Credential{
      organization_id: organization_id,
      provider_id: dialogflow.id,
      is_active: true,
      keys: %{
        url: Keyword.get(dflow, :url)
      },
      secrets: %{
        project_id: Keyword.get(dflow, :project_id),
        project_email: Keyword.get(dflow, :project_email)
      }
    })
  end

  def insert_goth_credentials(nil = _goth, _organization_id), do: nil

  def insert_goth_credentials(goth, organization_id) do
    {:ok, goth_db} = Repo.fetch_by(Provider, %{shortcode: "goth"})

    Repo.insert!(%Credential{
      organization_id: organization_id,
      provider_id: goth_db.id,
      is_active: true,
      keys: %{},
      secrets: %{
        json: Keyword.get(goth, :json)
      }
    })
  end

  def insert_chatbase_credentials(nil = _chatbase, _organization_id), do: nil

  def insert_chatbase_credentials(chatbase, organization_id) do
    {:ok, chatbase_db} = Repo.fetch_by(Provider, %{shortcode: "chatbase"})

    Repo.insert!(%Credential{
      organization_id: organization_id,
      provider_id: chatbase_db.id,
      is_active: true,
      keys: %{},
      secrets: %{
        api_key: Keyword.get(chatbase, :api_key)
      }
    })
  end


  def insert_gcs_credentials(gcs, organization_id) do
    {:ok, gcs_db} = Repo.fetch_by(Provider, %{shortcode: "google_cloud_storage"})

    Repo.insert!(%Credential{
          organization_id: organization_id,
          provider_id: gcs_db.id,
          is_active: true,
          keys: %{},
          secrets: %{
            email: Keyword.get(gcs, :email)
          }
                 })
  end

  def execute do
    secrets = get_secrets()
    update_gupshup_credentials(Keyword.get(secrets, :gupshup), 1)

    insert_dialogflow_credentials(Keyword.get(secrets, :dialogflow), 1)
    insert_goth_credentials(Keyword.get(secrets, :goth), 1)
    insert_chatbase_credentials(Keyword.get(secrets, :chatbase), 1)
    insert_gcs_credentials(Keyword.get(secrets, :gcs), 1)
  end
end

Glific.Seeds.Credentials.execute()
