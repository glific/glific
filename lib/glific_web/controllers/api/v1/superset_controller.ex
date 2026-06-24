defmodule GlificWeb.API.V1.SupersetController do
  @moduledoc """
  Superset Controller
  """
  use GlificWeb, :controller
  alias Glific.ThirdParty.Superset.ApiClient, as: SupersetClient
  alias Glific.Users.User

  @doc """
  Fetches a Superset embed token for the current user's organization.

  Returns 403 if the `superset_enabled` feature flag is not enabled for the org.
  """
  @spec embed_token(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def embed_token(conn, _params) do
    %User{organization_id: org_id} = conn.assigns[:current_user]

    with true <- FunWithFlags.enabled?(:superset_enabled, for: %{organization_id: org_id}),
         {:ok, %{token: token}} <- SupersetClient.get_embed_token(org_id) do
      json(conn, %{token: token})
    else
      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: %{status: 403, message: "Superset is not enabled for your organization."}
        })

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: %{
            status: 503,
            message:
              "Something went wrong loading the dashboard. Please retry, or contact support if the issue persists."
          }
        })
    end
  end
end
