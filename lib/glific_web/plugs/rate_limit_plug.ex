defmodule GlificWeb.RateLimitPlug do
  @moduledoc """
  Enforcing rate limits on our AP's both authenticated and non-authenticated
  """

  alias Plug.Conn

  @behaviour Plug

  # number of API calls via graphql / @time_period
  # number of unauthenticated API calls / @time_period
  @max_unauth_requests 50

  # @rate_limit API calls / minute
  # in seconds
  @time_period 60

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, opts) do
    user = conn.assigns[:current_user]

    # all our graphql api's are authenticated
    # if user is nil, it means someone is either creating
    # and/or logging in, in which case we'll have stricter limits
    if is_nil(user) do
      rate_limit_authentication(
        conn,
        Keyword.put(opts, :max_requests, @max_unauth_requests)
      )
    else
      rate_limit(conn, user, opts)
    end
  end

  defp rate_limit(conn, user, options) do
    case check_rate(conn, user, options) do
      # Do nothing, pass on to the next plug
      {:ok, _count} -> conn
      {:error, _count} -> render_error(conn)
    end
  end

  defp rate_limit_authentication(conn, options) do
    phone = get_in(conn.params, ["user", "phone"])

    options =
      if is_nil(phone),
        do: options,
        else: Keyword.put(options, :bucket_name, "Authorization: " <> phone)

    rate_limit(conn, nil, options)
  end

  defp check_rate(conn, user, options) do
    interval_milliseconds = (options[:time_period] || @time_period) * 1000

    max_requests =
      options[:max_requests] || Application.fetch_env!(:glific, :max_rate_limit_request)

    bucket_name = options[:bucket_name] || bucket_name(conn, user)

    ExRated.check_rate(bucket_name, interval_milliseconds, max_requests)
  end

  # Bucket name should be a combination of ip address and request path, like so:
  # "127.0.0.1:/api/v1/authorizations"
  defp bucket_name(conn, nil) do
    path = Enum.join(conn.path_info, "/")
    ip = GlificWeb.Tenants.remote_ip(conn)
    "#{ip}:#{path}"
  end

  # bucket name is user_id if user is set
  defp bucket_name(_conn, user) do
    "User: #{user.id}"
  end

  defp render_error(conn) do
    conn
    |> Conn.send_resp(429, "Rate limit exceeded")
    # Stop execution of further plugs, return response now
    |> Conn.halt()
  end
end
