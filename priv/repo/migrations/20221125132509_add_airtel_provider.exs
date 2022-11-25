defmodule Glific.Repo.Migrations.AddAirtelProvider do
  use Ecto.Migration

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  def change do
    add_airtel()
  end

  defp add_airtel do
    query = from p in Provider, where: p.shortcode == "airtel_iq"

    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Airtel IQ",
          shortcode: "airtel_iq",
          group: "bsp",
          description: "Setup Airtel IQ for WhatsApp message",
          is_required: true,
          keys: %{
            url: %{
              type: :string,
              label: "BSP Dashboard link",
              default: "https://www.airtel.in/business/b2b/airtel-iq/dashboard",
              view_only: true
            },
            api_end_point: %{
              type: :string,
              label: "API End Point",
              default: "https://iqwhatsapp.airtel.in/gateway/airtel-xchange/whatsapp-manager",
              view_only: false
            },
            handler: %{
              type: :string,
              label: "Inbound Message Handler",
              default: "Glific.Providers.Airtel.Message",
              view_only: true
            },
            worker: %{
              type: :string,
              label: "Outbound Message Worker",
              default: "Glific.Providers.Airtel.Worker",
              view_only: true
            }
          },
          secrets: %{
            user_id: %{
              type: :string,
              label: "Username",
              default: nil,
              view_only: false
            },
            password: %{
              type: :string,
              label: "Secret",
              default: nil,
              view_only: false
            }
          }
        })
  end
end
