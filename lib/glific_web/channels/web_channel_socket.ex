defmodule GlificWeb.WebChannelSocket do
  @moduledoc """
  Phoenix socket for the browser-based web channel. This is a separate socket from
  `GlificWeb.UserSocket` (which authenticates staff for the Absinthe GraphQL subscription
  API) — connections here authenticate as a single `Contact`, never a staff `User`.
  """

  use Phoenix.Socket

  alias Glific.Contacts
  alias Glific.RateLimit
  alias Glific.Repo
  alias GlificWeb.WebChannel.{Flag, Token}

  channel("web_channel:*", GlificWeb.WebChannel.RoomChannel)

  @impl true
  @spec connect(map(), Phoenix.Socket.t(), map()) :: {:ok, Phoenix.Socket.t()} | :error
  def connect(%{"token" => token}, socket, connect_info) do
    with :ok <- check_connect_rate_limit(connect_info),
         {:ok, payload} <- Token.verify_contact_token(token),
         true <- Flag.web_channel_enabled?(payload.org_id),
         # A fresh process with no context; permission-checked calls raise without it. No staff
         # user is behind a web connection, so run as the organization's root user.
         :ok <- put_org_context(payload.org_id),
         %Contacts.Contact{} = contact <- Contacts.get_contact!(payload.contact_id) do
      socket =
        socket
        |> assign(:current_contact, contact)
        |> assign(:organization_id, payload.org_id)
        |> assign(:token_exp, payload.exp)
        |> assign(:session_id, payload.session_id)
        |> assign(:session_started_at, payload.session_started_at)

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

  # Verifying a token is cheap but not free, and a connect that fails still costs a process and a
  # TLS handshake, so both budgets are charged before the token is even looked at.
  @spec check_connect_rate_limit(map()) :: :ok | {:error, :rate_limited} | {:error, :server_busy}
  defp check_connect_rate_limit(connect_info) do
    with :ok <-
           RateLimit.check(
             :rate_limit_web_channel_connect_ip,
             "web_channel_connect:#{client_ip(connect_info)}"
           ) do
      case RateLimit.check(:rate_limit_web_channel_connect_total, "web_channel_connect:total") do
        :ok -> :ok
        {:error, :rate_limited} -> {:error, :server_busy}
      end
    end
  end

  # Mirrors the endpoint's RemoteIp configuration: only the header gigalixir controls is trusted,
  # and it appends, so the rightmost entry is the real caller.
  @spec client_ip(map()) :: String.t()
  defp client_ip(connect_info) do
    forwarded =
      connect_info
      |> Map.get(:x_headers, [])
      |> Enum.filter(fn {name, _value} -> name == "x-forwarded-for" end)
      |> Enum.flat_map(fn {_name, value} -> String.split(value, ",") end)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case List.last(forwarded) do
      nil -> peer_ip(connect_info)
      address -> address
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
