defmodule Glific.Clients.Atecf do
  @moduledoc """
  Custom client functions for ATECF
  """

  @endpoint "https://staging.rwb.avniproject.org"
  @username Application.get_env(:glific, :avni_username)
  @password Application.get_env(:glific, :avni_password)
  use Tesla
  @spec headers(String.t() | nil) :: list()
  defp headers(token \\ nil) do
    header_list = [
      {"Content-Type", "application/json"}
    ]

    if is_nil(token) do
      header_list
    else
      header_list ++ [{"Authorization", token}]
    end
  end

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  def webhook("enable_avni_user", fields) do
    with {:ok, %{authToken: token}} <- get_auth_token(),
         {:ok, _} <- enable_user(token, fields.username) do
      %{success: true, username: fields.username}
    else
      {:error, reason} ->
        %{success: false, error: reason}
    end
  end

  @spec get_auth_token() :: :ok
  defp get_auth_token() do
    payload =
      %{
        "username" => @username,
        "password" => @password
      }
      |> Jason.encode!()

    post(@endpoint <> "/api/user/generateToken", payload, headers: headers())
    |> parse_api_response()
  end

  @spec enable_user(String.t(), String.t()) :: {:ok, any()} | {:error, String.t()}
  defp enable_user(token, username) do
    payload =
      %{
        "username" => username
      }
      |> Jason.encode!()

    post(@endpoint <> "/api/user/enable", payload, headers: headers())
    |> parse_api_response()
  end

  @spec parse_api_response({:ok, map()} | {:error, any()}) :: {:ok, map()} | {:error, any()}
  defp parse_api_response({:ok, %{body: body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, body}
  end

  defp parse_api_response({:ok, %{body: body, status: _status}}) do
    {:error, body.error}
  end

  defp parse_api_response({:error, _}) do
    {:error, "Avni api failed"}
  end
end
