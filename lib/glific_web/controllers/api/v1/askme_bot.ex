defmodule GlificWeb.API.V1.AskmeController do
  @moduledoc """
  AskMe bot Controller
  """
  use GlificWeb, :controller
  alias Glific.ThirdParty.OpenAI.AskmeBot

  @doc false
  @spec ask(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ask(conn, params) do
    case AskmeBot.askme(params) do
      {:ok, text} ->
        json(conn, %{response: text})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{status: 400, message: reason}})
    end
  end
end
