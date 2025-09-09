defmodule GlificWeb.API.V1.AskmeController do
  use GlificWeb, :controller
  alias Glific.ThirdParty.OpenAI.AskmeBot

  def ask(conn, params) do
    IO.inspect("coming here")

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
