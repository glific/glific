defmodule Glific.Repo.Seeds.AddGlificData_v0_5_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Repo
  }

  def up(_repo) do
    update_exisiting_providers()
  end

  defp update_exisiting_providers() do
    {:ok, gupshup} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

    {:ok, dialogflow} = Repo.fetch_by(Provider, %{shortcode: "dialogflow"})

    {:ok, goth} = Repo.fetch_by(Provider, %{shortcode: "goth"})

    {:ok, chatbase} = Repo.fetch_by(Provider, %{shortcode: "chatbase"})

    {:ok, bigquery} = Repo.fetch_by(Provider, %{shortcode: "bigquery"})

    {:ok, google_cloud_storage} = Repo.fetch_by(Provider, %{shortcode: "google_cloud_storage"})

    updated_gupshup_keys =
      Map.merge(gupshup.keys, %{
        bsp_limit: %{
          type: :integer,
          label: "BSP limit",
          default: 40,
          view_only: true
        }
      })

    # add bsp_limit in keys for gupshup
    # update all providers with description

    Repo.update!(
      Ecto.Changeset.change(gupshup, %{
        description: "Setup for WhatsApp message provider",
        keys: updated_gupshup_keys
      })
    )

    Repo.update!(
      Ecto.Changeset.change(dialogflow, %{
        description: "Setup connection with Dialogflow for advanced conversation flows"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(bigquery, %{
        description: "Setup connection with BigQuery for archiving data"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(goth, %{
        description: "Setup for GOTH which is required for Dialogflow and Chatbase"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(chatbase, %{
        description: "Integrate chatbase to create analytics and reports your way"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(google_cloud_storage, %{
        description: "Setup Cloud computing services with Google Cloud"
      })
    )
  end
end
