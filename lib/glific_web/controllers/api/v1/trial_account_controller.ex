defmodule GlificWeb.API.V1.TrialAccountController do
  use GlificWeb, :controller

  alias Glific.{Repo, Partners.Organization}
  import Ecto.Query

  def trial(conn, _params) do
    token = get_req_header(conn, "x-api-key") |> List.first()
    expected_token = get_token()

    if token == expected_token do
      case get_available_trial_account() do
        {:ok, organization} ->
          json(conn, %{
            success: true,
            data: %{
              login_url: "https://#{organization.shortcode}.glific.com",
              expires_at: organization.trial_expiration_date
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

  defp get_available_trial_account() do
    Repo.transaction(fn ->
      available_org =
        from(o in Organization,
          where: o.is_trial_org == true,
          where: is_nil(o.trial_expiration_date),
          limit: 1,
          lock: "FOR UPDATE"
        )
        |> Repo.one(skip_organization_id: true)

      case available_org do
        nil ->
          Repo.rollback(:no_available_accounts)

        org ->
          expiration_date =
            DateTime.utc_now()
            |> DateTime.truncate(:second)
            |> DateTime.add(14, :day)

          case Ecto.Changeset.change(org, %{
                 trial_expiration_date: expiration_date
               })
               |> Repo.update() do
            {:ok, updated_org} -> updated_org
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  defp get_token, do: Application.fetch_env!(:glific, __MODULE__)[:trial_account_token]
end
