defmodule Glific.Repo.Migrations.GupshupEnterprise do
  use Ecto.Migration
  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  def change do
    add_gupshup_enterprise()
  end

  defp add_gupshup_enterprise do
    query = from p in Provider, where: p.shortcode == "gupshup_enterprise"

    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Gupshup Enterprise",
          shortcode: "gupshup_enterprise",
          group: "bsp",
          description: "Setup Gupshup Enterprise for WhatsApp message",
          is_required: true,
          keys: %{
            url: %{
              type: :string,
              label: "BSP Home Page",
              default: "https://enterprise.smsgupshup.com/",
              view_only: true
            },
            api_end_point: %{
              type: :string,
              label: "API End Point",
              default: "https://media.smsgupshup.com/GatewayAPI/rest",
              view_only: false
            },
            handler: %{
              type: :string,
              label: "Inbound Message Handler",
              default: "Glific.Providers.Gupshup.Enterprise.Message",
              view_only: true
            },
            worker: %{
              type: :string,
              label: "Outbound Message Worker",
              default: "Glific.Providers.Gupshup.Enterprise.Worker",
              view_only: true
            }
          },
          secrets: %{
            hsm_user_id: %{
              type: :string,
              label: "HSM User ID",
              default: nil,
              view_only: false
            },
            hsm_password: %{
              type: :string,
              label: "HSM Password",
              default: nil,
              view_only: false
            },
            two_way_user_id: %{
              type: :string,
              label: "Two way User ID",
              default: nil,
              view_only: false
            },
            two_way_password: %{
              type: :string,
              label: "Two way Password",
              default: nil,
              view_only: false
            }
          }
        })
  end
end
