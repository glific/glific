defmodule GlificWeb.APIAuthPlug do
  @moduledoc false
  use Pow.Plug.Base

  require Logger

  alias Plug.Conn
  alias Pow.{Config, Plug, Store.CredentialsCache}
  alias PowPersistentSession.Store.PersistentSessionCache

  alias GlificWeb.Endpoint

  @doc """
  Fetches the user from access token.
  """
  @impl true
  @spec fetch(Conn.t(), Config.t()) :: {Conn.t(), map() | nil}
  def fetch(conn, config) do
    with {:ok, signed_token} <- fetch_access_token(conn),
         {user, _metadata} <- get_credentials(conn, signed_token, config) do
      {conn, user}
    else
      _any -> {conn, nil}
    end
  end

  @doc """
  helper function that can be called from the socket token verification to
  validate the token
  """
  # @spec get_credentials(Conn.t(), binary(), Config.t() | nil) :: {map(), [any()]} | nil
  def get_credentials(conn, signed_token, config) do
    with {:ok, token} <- verify_token(conn, signed_token, config),
         {user, metadata} <- CredentialsCache.get(store_config(config), token) do
      {user, metadata}
    else
      _any -> nil
    end
  end

  @ttl 30

  @doc """
  Creates an access and renewal token for the user.

  The tokens are added to the `conn.private` as `:api_access_token` and
  `:api_renewal_token`. The renewal token is stored in the access token
  metadata and vice versa.
  """
  @impl true
  @spec create(Conn.t(), map(), Config.t()) :: {Conn.t(), map()}
  def create(conn, user, config) do
    Logger.info("Creating tokens: user_id: '#{user.id}'")

    store_config = store_config(config)

    # 30 mins in seconds - this is the default, we wont change it
    token_expiry_time = DateTime.utc_now() |> DateTime.add(@ttl * 60, :second)
    fingerprint = conn.private[:pow_api_session_fingerprint] || Pow.UUID.generate()
    access_token = Pow.UUID.generate()
    renewal_token = Pow.UUID.generate()

    conn =
      conn
      |> Conn.put_private(:api_access_token, sign_token(conn, access_token, config))
      |> Conn.put_private(:api_renewal_token, sign_token(conn, renewal_token, config))
      |> Conn.put_private(:api_token_expiry_time, token_expiry_time)

    CredentialsCache.put(
      store_config |> Keyword.put(:ttl, :timer.minutes(@ttl)),
      access_token,
      {user, fingerprint: fingerprint, renewal_token: renewal_token}
    )

    PersistentSessionCache.put(
      store_config,
      renewal_token,
      {[id: user.id], fingerprint: fingerprint, access_token: access_token}
    )

    {conn, user}
  end

  @doc """
  Delete the access token from the cache.

  The renewal token is deleted by fetching it from the access token metadata.
  """
  @impl true
  @spec delete(Conn.t(), Config.t()) :: Conn.t()
  def delete(conn, config) do
    Logger.info("Deleting tokens: user_id: '#{conn.assigns[:current_user].id}'")

    store_config = store_config(config)

    with {:ok, signed_token} <- fetch_access_token(conn),
         {:ok, token} <- verify_token(conn, signed_token, config),
         {_user, metadata} <- CredentialsCache.get(store_config, token) do
      PersistentSessionCache.delete(store_config, metadata[:renewal_token])
      CredentialsCache.delete(store_config, token)

      Endpoint.broadcast("users_socket:" <> metadata[:fingerprint], "disconnect", %{})
    else
      _any -> :ok
    end

    conn
  end

  @doc """
  Creates new tokens using the renewal token.

  The access token, if any, will be deleted by fetching it from the renewal
  token metadata. The renewal token will be deleted from the store after the
  it has been fetched.

  `:pow_api_session_fingerprint` will be set in `conn.private` with the
  `:fingerprint` fetched from the metadata, to ensure it will be persisted in
  the tokens generated in `create/2`.
  """
  @spec renew(Conn.t(), Config.t()) :: {Conn.t(), map() | nil}
  def renew(conn, config) do
    store_config = store_config(config)

    with {:ok, signed_token} <- fetch_access_token(conn),
         {:ok, token} <- verify_token(conn, signed_token, config),
         {clauses, metadata} <- PersistentSessionCache.get(store_config, token) do
      Logger.info("Renewing token succeeded")

      CredentialsCache.delete(store_config, metadata[:access_token])
      PersistentSessionCache.delete(store_config, token)

      conn
      |> Conn.put_private(:pow_api_session_fingerprint, metadata[:fingerprint])
      |> load_and_create_session({clauses, metadata}, config)
    else
      _any ->
        Logger.error("Renewing token failed")
        {conn, nil}
    end
  end

  @doc """
  Delete all user sessions after user resets or updates the password
  """
  @spec delete_all_user_sessions(Config.t(), map()) :: :ok
  def delete_all_user_sessions(config, user) do
    store_config = store_config(config)

    CredentialsCache.sessions(store_config, user)
    |> Enum.each(fn token ->
      {_user, metadata} = CredentialsCache.get(store_config, token)
      PersistentSessionCache.delete(store_config, metadata[:renewal_token])
      CredentialsCache.delete(store_config, token)

      Endpoint.broadcast("users_socket:" <> metadata[:fingerprint], "disconnect", %{})
    end)
  end

  defp load_and_create_session(conn, {clauses, _metadata}, config) do
    case Pow.Operations.get_by(clauses, config) do
      nil -> {conn, nil}
      user -> create(conn, user, config)
    end
  end

  defp sign_token(conn, token, config) do
    Plug.sign_token(conn, signing_salt(), token, config)
  end

  defp signing_salt, do: Atom.to_string(__MODULE__)

  defp fetch_access_token(conn) do
    case Conn.get_req_header(conn, "authorization") do
      [token | _rest] -> {:ok, token}
      _any -> :error
    end
  end

  defp verify_token(conn, token, config),
    do: Plug.verify_token(conn, signing_salt(), token, config)

  defp store_config(config) do
    backend = Config.get(config, :cache_store_backend, Pow.Store.Backend.MnesiaCache)

    [backend: backend]
  end
end
