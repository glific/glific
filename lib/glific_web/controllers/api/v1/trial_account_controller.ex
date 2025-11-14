defmodule GlificWeb.API.V1.TrialAccountController do
  use GlificWeb, :controller

  alias Glific.{Repo, Partners.Organization}
  import Ecto.Query

  def trial(conn, _params) do
    token = get_req_header(conn, "x-api-key") |> List.first()
    expected_token = "8fSLZ035pPUOMpGZUTvS2swm5xrRLhVxb79f"

    if token == expected_token do
      case get_available_trial_account() |> IO.inspect() do
        {:ok, organization} ->
          json(conn, %{
            success: true,
            data: %{
              login_url: "https://#{organization.name}.glific.com",
              expires_at: organization.expiration_date
            }
          })

        {:error, :no_available_accounts} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{
            success: false,
            error: "No trial accounts available at the moment"
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{success: false, error: "Invalid API token"})
    end
  end

  defp get_available_trial_account do
    available_org =
      from(o in Organization,
        where: o.is_trial_org == true,
        where: is_nil(o.expiration_date),
        limit: 1
      )
      |> Repo.one(skip_organization_id: true)

    case available_org do
      nil -> {:error, :no_available_accounts}
      org -> {:ok, org}
    end
  end
end
