defmodule GlificWeb.UserSocket do
  @moduledoc false

  use Absinthe.GraphqlWS.Socket, schema: GlificWeb.Schema

  require Logger

  alias GlificWeb.APIAuthPlug

  # create pow_config for authentication
  @pow_config otp_app: :glific

  @impl true
  def handle_init(params, socket) do
    user_id = params["userId"]
    token = params["authToken"]

    %Plug.Conn{secret_key_base: socket.endpoint.config(:secret_key_base)}
    |> APIAuthPlug.get_credentials(token, @pow_config)
    |> case do
      nil ->
        Logger.info("Connecting to socket failed: user_id: '#{user_id}'")
        {:error, %{message: "Connection closed"}, socket}

      {user, metadata} ->
        Logger.info("Verifying tokens: user_id: '#{user.id}'")
        fingerprint = Keyword.fetch!(metadata, :fingerprint)

        socket =
          socket
          |> assign(:assigns, fingerprint)
          |> assign(:assigns, user)
          |> assign_context(current_user: user)

        Glific.Repo.put_current_user(user)
        Glific.Repo.put_organization_id(user.organization_id)

        {:ok, %{name: user.name}, socket}
    end
  end

  # This function will be called when there was no authentication information
  def handle_init(_params, _socket), do: :error
end
