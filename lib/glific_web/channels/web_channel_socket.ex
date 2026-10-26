defmodule GlificWeb.WebChannelSocket do
  @moduledoc """
  Phoenix socket for the browser-based web channel. This is a separate socket from
  `GlificWeb.UserSocket` (which authenticates staff for the Absinthe GraphQL subscription
  API) — connections here authenticate as a single `Contact`, never a staff `User`.

  A connection presents a `GlificWeb.WebChannel.Token`, either Glific's own (phone and one-time
  code login) or one signed by an NGO's backend when its own system manages its users. Both are
  verified the same way, against the secret of the organization the request host belongs to.
  """

  use Phoenix.Socket

  alias Glific.Contacts
  alias Glific.RateLimit
  alias Glific.Repo
  alias GlificWeb.SubdomainPlug
  alias GlificWeb.WebChannel.{Flag, Token}

  channel("web_channel:*", GlificWeb.WebChannel.RoomChannel)

  @forwarding_headers ~w[x-forwarded-for]

  @impl true
  @spec connect(map(), Phoenix.Socket.t(), map()) :: {:ok, Phoenix.Socket.t()} | :error
  def connect(%{"token" => token}, socket, connect_info) do
    with :ok <- check_connect_rate_limit(connect_info),
         {:ok, session} <- authenticate(token, connect_info) do
      socket =
        socket
        |> assign(:current_contact, session.contact)
        |> assign(:organization_id, session.organization_id)
        |> assign(:token_exp, session.token_exp)
        |> assign(:session_id, session.session_id)
        |> assign(:session_started_at, session.session_started_at)

      {:ok, socket}
    else
      # The one refusal a caller is allowed to tell apart: it is about us, not about them.
      {:error, :server_busy} -> {:error, :server_busy}
      _ -> :error
    end
  rescue
    # Undifferentiated on purpose: a caller must never learn why connect refused it.
    _ -> :error
  end

  def connect(_params, _socket, _connect_info), do: :error

  @doc """
  Shape the HTTP response a refused connect gets, so a busy node is distinguishable from a bad
  token.
  """
  @spec handle_connect_error(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def handle_connect_error(conn, :server_busy), do: Plug.Conn.send_resp(conn, 503, "")
  def handle_connect_error(conn, _reason), do: Plug.Conn.send_resp(conn, 403, "")

  @spec authenticate(String.t(), map()) :: {:ok, map()} | :error
  defp authenticate(token, connect_info) do
    with {:ok, organization_id} <- organization_from_host(connect_info),
         :ok <- enter_organization(organization_id),
         {:ok, claims} <- Token.verify(organization_id, token),
         {:ok, contact} <- resolve_contact(claims) do
      record_optin(claims, organization_id)

      {:ok,
       %{
         contact: contact,
         organization_id: organization_id,
         token_exp: claims.exp,
         session_id: Map.get(claims, :session_id, "web:" <> claims.sub),
         session_started_at: Map.get(claims, :session_started_at, System.system_time(:second))
       }}
    else
      _refused -> :error
    end
  end

  # A Glific session names a contact that already signed in, so it never creates one: a session
  # outliving its erased contact would otherwise mint a ghost holding that phone's web identity
  # and block the phone's next sign-in.
  @spec resolve_contact(Token.claims()) :: {:ok, Contacts.Contact.t()} | {:error, any()}
  defp resolve_contact(%{session_id: _session_id} = claims),
    do: Contacts.fetch_by_identity(:web, claims.sub)

  defp resolve_contact(claims), do: Contacts.maybe_create_contact(claims, :web, claims.sub)

  @spec record_optin(Token.claims(), non_neg_integer()) :: :ok
  defp record_optin(%{optin: true, sub: sub}, organization_id) do
    case Contacts.contact_opted_in(:web, sub, %{organization_id: organization_id}, method: "NGO") do
      {:ok, _contact} ->
        :ok

      # The user is signed in by now; a consent write that fails must not refuse the connection.
      {:error, reason} ->
        Glific.log_error(
          "Web channel opt-in not recorded: #{Glific.SafeLog.safe_inspect(reason)}"
        )

        :ok
    end
  end

  defp record_optin(_claims, _organization_id), do: :ok

  @spec organization_from_host(map()) :: {:ok, non_neg_integer()} | :error
  defp organization_from_host(%{uri: %URI{host: host}}),
    do: SubdomainPlug.organization_id_for_host(host)

  defp organization_from_host(_connect_info), do: :error

  # A fresh process with no context; permission-checked calls raise without it. No staff user is
  # behind a web connection, so run as the organization's root user.
  @spec enter_organization(non_neg_integer()) :: :ok | :error
  defp enter_organization(organization_id) do
    if Flag.web_channel_enabled?(organization_id),
      do: put_org_context(organization_id),
      else: :error
  end

  # Verifying a token is cheap but not free, and a connect that fails still costs a process and a
  # TLS handshake, so both budgets are charged before the token is even looked at.
  @spec check_connect_rate_limit(map()) :: :ok | {:error, :rate_limited} | {:error, :server_busy}
  defp check_connect_rate_limit(connect_info) do
    with :ok <-
           RateLimit.check(
             :rate_limit_web_channel_connect_ip,
             "web_channel_connect:#{client_ip(connect_info)}"
           ) do
      check_total_capacity()
    end
  end

  # Its own function so the two budgets read as one `with` above, and so that exhausting the node
  # is distinguishable from one address being throttled: only this one answers 503.
  @spec check_total_capacity :: :ok | {:error, :server_busy}
  defp check_total_capacity do
    case RateLimit.check(:rate_limit_web_channel_connect_total, "web_channel_connect:total") do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :server_busy}
    end
  end

  # Selected by RemoteIp rather than by hand, so this agrees with conn.remote_ip everywhere else:
  # taking the last entry would pick an appended private hop instead of the caller.
  @spec client_ip(map()) :: String.t()
  defp client_ip(connect_info) do
    connect_info
    |> Map.get(:x_headers, [])
    |> RemoteIp.from(headers: @forwarding_headers)
    |> case do
      nil -> peer_ip(connect_info)
      address -> address |> :inet_parse.ntoa() |> to_string()
    end
  end

  @spec peer_ip(map()) :: String.t()
  defp peer_ip(%{peer_data: %{address: address}}),
    do: address |> :inet_parse.ntoa() |> to_string()

  defp peer_ip(_connect_info), do: "unknown"

  @spec put_org_context(non_neg_integer()) :: :ok
  defp put_org_context(org_id) do
    Repo.put_process_state(org_id)
    :ok
  end

  @impl true
  @spec id(Phoenix.Socket.t()) :: String.t()
  def id(socket), do: "web_socket:#{socket.assigns.current_contact.id}"
end
