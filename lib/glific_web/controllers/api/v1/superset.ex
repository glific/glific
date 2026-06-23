defmodule GlificWeb.API.V1.SupersetController do
  @moduledoc """
  Superset Controller
  """
  use GlificWeb, :controller
  alias Glific.ThirdParty.Superset.ApiClient, as: SupersetClient
  alias Glific.Users.User

  @doc """
  Fetches a Superset embed token for the current user's organization.
  """
  @spec embed_token(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def embed_token(conn, _params) do
    with %User{organization_id: org_id} <- conn.assigns.current_user,
         {:ok, %{token: token}} <- SupersetClient.get_embed_token(org_id) do
      json(conn, %{token: token})
    else
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{status: 401, message: "Authentication failure"}})

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
