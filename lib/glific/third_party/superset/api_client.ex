defmodule Glific.ThirdParty.Superset.ApiClient do
  @moduledoc """
  HTTP client for the Superset embed API.

  Handles the three-step auth flow required to obtain a guest embed token:
    1. POST `/security/login` — exchange credentials for an access token
    2. GET `/security/csrf_token` — obtain a CSRF token and session cookie
    3. POST `/security/guest_token` — obtain the embed token for a dashboard

  Configuration is read at runtime from `:glific, Glific.ThirdParty.Superset.ApiClient`
  (see `config/runtime.exs`). Required keys: `base_url`, `dashboard_id`, `guest_username`,
  `username`, `password`.
  """

  require Logger

  alias Glific.SafeLog

  defmodule Error do
    @moduledoc """
    Custom exception for Superset API failures.

    Using a dedicated exception type groups all Superset errors under a single class in
    AppSignal, keeping them isolated from generic RuntimeErrors and making alert routing easier.
    """
    defexception [:message, :status_code, :reason, :organization_id]
  end

  @doc """
  Fetches a Superset guest embed token for the given organization.

  Runs the full three-step auth flow against the configured Superset instance and returns
  the embed token on success.

  ## Examples

      iex> Glific.ThirdParty.Superset.ApiClient.get_embed_token(1)
      {:ok, %{token: "eyJ..."}}

  """
  @spec get_embed_token(non_neg_integer()) :: {:ok, map()} | {:error, any()}
  def get_embed_token(_organization_id) do
    username = superset_config(:username)
    password = superset_config(:password)

    with {:ok, %{access_token: token}} <- get_access_token(username, password),
         {:ok, %{result: csrf_token, cookie: cookie}} <- get_csrf_token(token) do
      fetch_embed_token(token, csrf_token, cookie)
    end
  end

  @spec get_access_token(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  defp get_access_token(username, password) do
    payload = %{
      username: username,
      password: password,
      refresh: true,
      provider: "db"
    }

    client()
    |> Tesla.post("/security/login", payload)
    |> parse_response()
  end

  @spec get_csrf_token(String.t()) :: {:ok, map()} | {:error, any()}
  defp get_csrf_token(access_token) do
    access_token
    |> client()
    |> Tesla.get("/security/csrf_token/")
    |> parse_response()
  end

  @spec fetch_embed_token(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, any()}
  defp fetch_embed_token(access_token, csrf_token, cookie) do
    payload = %{
      user: %{
        username: superset_config(:guest_username),
        first_name: "Glific",
        last_name: "Dev"
      },
      resources: [%{type: "dashboard", id: superset_config(:dashboard_id)}],
      # RLS temporarily disabled to allow org filtering via the Superset UI.
      # Restore by adding organization_id as a parameter and setting:
      # rls: [%{clause: "organization_id = #{organization_id}"}]
      rls: []
    }

    access_token
    |> client(csrf_token, cookie)
    |> Tesla.post("/security/guest_token/", payload)
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, any()}
  defp parse_response({:ok, %Tesla.Env{status: status, body: body, headers: headers}})
       when status in 200..299 do
    Appsignal.increment_counter("superset.embed_token.success", 1, %{})

    case Enum.find(headers, fn {k, _} -> k == "set-cookie" end) do
      {_, cookie} -> {:ok, Map.put(body, :cookie, cookie)}
      nil -> {:ok, body}
    end
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}) do
    upstream_msg = Map.get(body, :message, "no message returned")

    Glific.log_exception(
      %Error{
        message: "Superset API error: HTTP #{status} — #{upstream_msg}",
        status_code: status,
        reason: body
      },
      namespace: "superset",
      tags: %{status: status}
    )

    {:error, %{status: status, body: body}}
  end

  defp parse_response({:error, reason}) do
    Glific.log_exception(
      %Error{
        message: "Superset API transport error: #{SafeLog.safe_inspect(reason)}",
        reason: reason
      },
      namespace: "superset"
    )

    {:error, reason}
  end

  @spec client(String.t() | nil, String.t() | nil, String.t() | nil) :: Tesla.Client.t()
  defp client(access_token \\ nil, csrf_token \\ nil, session \\ nil) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, superset_config(:base_url)},
        {Tesla.Middleware.FollowRedirects, max_redirects: 5},
        {Tesla.Middleware.Headers, headers(access_token, csrf_token, session)},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Logger, filter_headers: ["Authorization", "X-CSRFToken"]},
        {Tesla.Middleware.Telemetry, metadata: %{provider: "Superset", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end

  @spec headers(String.t() | nil, String.t() | nil, String.t() | nil) :: list()
  defp headers(access_token, csrf_token, session) do
    base = [{"content-type", "application/json"}]

    base =
      if is_nil(access_token) do
        base
      else
        base ++ [{"Authorization", "Bearer " <> access_token}]
      end

    if is_nil(csrf_token) do
      base
    else
      base ++
        [
          {"X-CSRFToken", csrf_token},
          {"Referer", superset_config(:base_url)},
          {"cookie", session}
        ]
    end
  end

  @spec superset_config() :: keyword()
  defp superset_config, do: Application.fetch_env!(:glific, __MODULE__)

  @spec superset_config(atom()) :: any()
  defp superset_config(key), do: superset_config()[key]
end
