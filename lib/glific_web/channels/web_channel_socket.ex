defmodule GlificWeb.WebChannelSocket do
  @moduledoc """
  Phoenix socket for the browser-based web channel. This is a separate socket from
  `GlificWeb.UserSocket` (which authenticates staff for the Absinthe GraphQL subscription
  API) — connections here authenticate as a single `Contact`, never a staff `User`.
  """

  use Phoenix.Socket

  alias Glific.Contacts
  alias Glific.Repo
  alias GlificWeb.WebChannel.Token

  channel("web_channel:*", GlificWeb.WebChannel.RoomChannel)

  @impl true
  @spec connect(map(), Phoenix.Socket.t(), map()) :: {:ok, Phoenix.Socket.t()} | :error
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, %{contact_id: contact_id, org_id: org_id}} <- Token.verify_contact_token(token),
         # The connect process is fresh (no org/user context). Permission-checked context
         # calls like Contacts.get_contact!/1 raise "Invalid user" without it — same rule an
         # Oban worker follows. There's no staff user behind a web connection, so run as the
         # organization's root user.
         :ok <- put_org_context(org_id),
         %Contacts.Contact{} = contact <- Contacts.get_contact!(contact_id) do
      socket =
        socket
        |> assign(:current_contact, contact)
        |> assign(:organization_id, org_id)

      {:ok, socket}
    else
      _ -> :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Establish tenant + root-user context for the connect process so permission-checked
  # queries succeed. Always returns :ok so it slots into the connect/3 `with` chain.
  @spec put_org_context(non_neg_integer()) :: :ok
  defp put_org_context(org_id) do
    Repo.put_process_state(org_id)
    :ok
  end

  @impl true
  @spec id(Phoenix.Socket.t()) :: String.t()
  def id(socket), do: "web_socket:#{socket.assigns.current_contact.id}"
end
