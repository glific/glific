defmodule GlificWeb.WordpressController do
  use GlificWeb, :controller

  alias Glific.{Repo, Partners.Organization}
  import Ecto.Query

  def trial(conn, params) do
    IO.inspect(params, label: "Received params")

    # Verify token
    token = get_req_header(conn, "x-api-key") |> List.first()
    expected_token = "8fSLZ035pPUOMpGZUTvS2swm5xrRLhVxb79f"

    if token == expected_token do
      case allocate_trial_account(params) do
        {:ok, organization} ->
          json(conn, %{
            success: true,
            message: "Trial account allocated successfully",
            data: %{
              organization_id: organization.id,
              organization_name: organization.name,
              login_url: "https://glific.test:3000/users/log_in",
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

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{success: false, error: "Failed to allocate account"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{success: false, error: "Invalid API token"})
    end
  end

  defp allocate_trial_account(params) do
    Repo.transaction(fn ->
      available_org =
        from(o in Organization,
          where: o.is_trial_account == true,
          where: is_nil(o.trial_expiration_date),
          limit: 1,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case available_org do
        nil ->
          Repo.rollback(:no_available_accounts)

        org ->
          expiration_date = DateTime.utc_now() |> DateTime.add(14, :day)

          changeset =
            Organization.changeset(org, %{
              trial_expiration_date: expiration_date,
              trial_user_name: params["name"],
              trial_user_email: params["email"],
              trial_user_phone: params["phone"]
            })

          case Repo.update(changeset) do
            {:ok, updated_org} -> updated_org
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end
end
