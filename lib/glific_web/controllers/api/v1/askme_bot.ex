defmodule GlificWeb.API.V1.AskmeController do
  @moduledoc """
  AskMe bot Controller
  """
  alias Glific.Users.User
  use GlificWeb, :controller
  alias Glific.AskmeBot

  @doc false
  @spec ask(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ask(conn, params) do
    with %User{organization_id: org_id} <- conn.assigns.current_user,
         {:ok, text} <- AskmeBot.askme(params, org_id) do
      json(conn, %{response: text})
    else
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{status: 401, message: "Authentication failure"}})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{status: 400, message: reason}})
    end
  end
end
