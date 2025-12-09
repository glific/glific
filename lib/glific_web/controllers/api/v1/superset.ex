defmodule GlificWeb.API.V1.SupersetController do
  @moduledoc """
  Superset Controller
  """
  alias Glific.Users.User
  use GlificWeb, :controller

  @dashborad_id "71f4c8d9-f9c6-4b9d-9b28-80c550681b7f"

  @doc false
  @spec embed_token(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def embed_token(conn, _params) do
    with %User{organization_id: org_id} <- conn.assigns.current_user,
         {:ok, %{token: token}} <- get_embed_token(org_id) do
      json(conn, %{token: token})
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{status: 401, message: "Authentication failure"}})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{status: 400, message: reason}})
    end
  end

  def get_embed_token(organization_id) do
    username = Application.fetch_env!(:glific, :superset_username)
    password = Application.fetch_env!(:glific, :superset_password)

    with {:ok, %{access_token: token}} <- get_access_token(username, password),
         {:ok, %{result: csrf_token, cookie: cookie}} <- get_csrf_token(token) do
      fetch_embed_token(organization_id, token, csrf_token, cookie)
    end
  end

  def get_access_token(username, password) do
    login_url = "https://kaapi.projecttech4dev.org/api/v1/security/login"

    payload = %{
      username: username,
      password: password,
      refresh: true,
      provider: "db"
    }

    client()
    |> Tesla.post(login_url, payload)
    |> parse_response()
  end

  def get_csrf_token(access_token) do
    url = "https://kaapi.projecttech4dev.org/api/v1/security/csrf_token"

    client(access_token)
    |> Tesla.get(url)
    |> parse_response()
  end

  def fetch_embed_token(_organization_id, access_token, csrf_token, cookie) do
    url = "https://kaapi.projecttech4dev.org/api/v1/security/guest_token"

    payload = %{
      user: %{
        username: "anandu_test",
        first_name: "anandu_test",
        last_name: "anandu_test"
      },
      resources: [%{type: "dashboard", id: @dashborad_id}],
      # Uncomment this to enable fetching data of only the current user's org.
      # rls: [%{clause: "organization_id=#{organization_id}"}]
      rls: []
    }

    client(access_token, csrf_token, cookie)
    |> Tesla.post(url, payload)
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, any()}
  defp parse_response({:ok, %Tesla.Env{status: status, body: body, headers: headers}})
       when status in 200..299 do
    {_, cookie} =
      Enum.find(headers, {nil, "random_cookie"}, fn header -> elem(header, 0) == "set-cookie" end)

    {:ok, body |> Map.put(:cookie, cookie)}
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}) do
    {:error, %{status: status, body: body}}
  end

  defp parse_response(error) do
    error
  end

  defp client(access_token \\ nil, csrf_token \\ nil, session \\ nil) do
    config = [
      {Tesla.Middleware.FollowRedirects, max_redirects: 5},
      {Tesla.Middleware.Headers, headers(access_token, csrf_token, session)},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]}
    ]

    Tesla.client(config)
  end

  defp headers(access_token, csrf_token, session) do
    base = [
      {"content-type", "application/json"}
    ]

    base =
      if not is_nil(access_token) do
        base ++ [{"Authorization", "Bearer " <> access_token}]
      else
        base
      end

    if not is_nil(csrf_token) do
      base ++
        [
          {"X-CSRFToken", csrf_token},
          {"Referer", "https://kaapi.projecttech4dev.org/api/v1"},
          {"cookie", session}
        ]
    else
      base
    end
  end
end
