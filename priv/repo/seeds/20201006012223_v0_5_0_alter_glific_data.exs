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
    # add pseudo credentials for gupshup and glifproxy
    {:ok, gupshup} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})
    {:ok, glifproxy} = Repo.fetch_by(Provider, %{shortcode: "glifproxy"})
    {:ok, dialogflow} = Repo.fetch_by(Provider, %{shortcode: "dialogflow"})
    {:ok, goth} = Repo.fetch_by(Provider, %{shortcode: "goth"})
    {:ok, chatbase} = Repo.fetch_by(Provider, %{shortcode: "chatbase"})
    {:ok, google_cloud_storage} = Repo.fetch_by(Provider, %{shortcode: "google_cloud_storage"})

    # update providers with description
    Repo.update!(
      Ecto.Changeset.change(gupshup, %{
        description: "Setup for WhatsApp message provider"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(glifproxy, %{
        description: "Setup for Glific simulator"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(dialogflow, %{
        description: "Setup connection with Dialogflow for advanced conversation flows"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(goth, %{
        description: "Setup for GOTH which is required for Dialogflow and Chatbase"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(chatbase, %{
        description: "Setup for Chatbase"
      })
    )

    Repo.update!(
      Ecto.Changeset.change(google_cloud_storage, %{
        description: "Setup for Google Cloud Storage"
      })
    )
  end
end
