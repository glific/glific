defmodule GlificWeb.UserSocket do
  @moduledoc false
  use Phoenix.Socket

  use Absinthe.Phoenix.Socket,
    schema: GlificWeb.Schema

  alias GlificWeb.APIAuthPlug

  ## Channels
  # channel "room:*", GlificWeb.RoomChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(%{"token" => token} = _params, socket, %{pow_config: config} = _connect_info) do
    %Plug.Conn{secret_key_base: socket.endpoint.config(:secret_key_base)}
    |> APIAuthPlug.get_credentials(token, config)
    |> case do
      nil ->
        :error

      {user, metadata} ->
        fingerprint = Keyword.fetch!(metadata, :fingerprint)

        socket =
          socket
          |> assign(:session_fingerprint, fingerprint)
          |> assign(:user_id, user.id)
          |> assign(:organization_id, user.organization_id)
          |> Absinthe.Phoenix.Socket.put_options(context: %{current_user: user})

        {:ok, socket}
    end
  end

  # This function will be called when there was no authentication information
  def connect(_params, _socket, _connect_info) do
    :error
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     GlificWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(%{assigns: %{session_fingerprint: session_fingerprint}}),
    do: "user_socket:#{session_fingerprint}"

  # dont think we need this, we should allow it to fail
  # def id(_socket), do: nil
end
