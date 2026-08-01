defmodule GlificWeb.WebChannel.RoomChannel do
  @moduledoc """
  The Phoenix channel a browser contact joins to hold its own web channel conversation:
  fetching recent history, sending/receiving messages live, and updating its display name.

  Topic shape: `"web_channel:<contact_id>"` — a contact may only join its own topic (enforced
  in `join/3` against `socket.assigns.current_contact`, set during `GlificWeb.WebChannelSocket`
  authentication).
  """

  use GlificWeb, :channel

  alias Glific.{Communications.WebMessage, Contacts, Messages, Repo}
  alias GlificWeb.WebChannel.MessageSerializer
  alias GlificWeb.WebChannel.Presence

  @page_size 100

  @impl true
  @spec join(String.t(), map(), Phoenix.Socket.t()) ::
          {:ok, map(), Phoenix.Socket.t()} | {:error, map()}
  def join("web_channel:" <> contact_id, _params, socket) do
    if contact_id == to_string(socket.assigns.current_contact.id) do
      # The channel runs in its own process, separate from the connect/3 process, so org
      # context (and a current_user, needed by permission-checked context calls like
      # Contacts.update_contact/2) has to be re-established here — same requirement as an
      # Oban worker's perform/1. There's no staff user behind a web channel connection, so
      # we run as the organization's root user.
      Repo.put_process_state(socket.assigns.organization_id)

      send(self(), :after_join)

      # Newest-last so the frontend can render top-to-bottom without re-sorting.
      messages =
        contact_id
        |> String.to_integer()
        |> Messages.list_conversation_messages("web", %{limit: @page_size, offset: 0})
        |> Enum.reverse()
        |> Enum.map(&MessageSerializer.serialize/1)

      {:ok, %{messages: messages}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  @spec handle_info(:after_join, Phoenix.Socket.t()) :: {:noreply, Phoenix.Socket.t()}
  def handle_info(:after_join, socket) do
    contact_id = socket.assigns.current_contact.id

    {:ok, _} =
      Presence.track(socket, "contact:#{contact_id}", %{
        online_at: DateTime.utc_now()
      })

    {:noreply, socket}
  end

  # Glific.Processor.ConsumerWorkerMock (test env only) notifies the caller process once it
  # has "processed" a message handed off via Communications.Message.process_message/1 — the
  # real ConsumerWorker does not. Since inbound flow-processing happens in this channel
  # process, swallow that notification here rather than crash.
  def handle_info(:received_message_to_process, socket), do: {:noreply, socket}

  @impl true
  @spec handle_in(String.t(), map(), Phoenix.Socket.t()) ::
          {:reply, {:ok, map()} | :ok | {:error, map()}, Phoenix.Socket.t()}
  def handle_in("load_more", %{"offset" => offset}, socket) do
    contact_id = socket.assigns.current_contact.id

    messages =
      contact_id
      |> Messages.list_conversation_messages("web", %{limit: @page_size, offset: offset})
      |> Enum.reverse()
      |> Enum.map(&MessageSerializer.serialize/1)

    {:reply, {:ok, %{messages: messages}}, socket}
  end

  def handle_in("new_message", %{"body" => body}, socket) do
    contact = socket.assigns.current_contact

    # No bsp_message_id here on purpose: the web channel has no BSP, and messages has a
    # unique_constraint([:bsp_message_id, :organization_id]). A client-supplied id (e.g. a
    # guessed/duplicate value from the payload) could collide with a real BSP id or silently
    # drop the browser's own message on create_message/1 failure. Leave it nil — Postgres
    # allows many nulls under that unique index.
    #
    # TODO: media handling — this prototype is text-first. Once the frontend can upload
    # media, extend this clause (or add a dedicated "new_media_message" event) to build the
    # `message_media` record before calling receive_message/2 with the appropriate type.
    :ok =
      WebMessage.receive_message(
        %{
          sender: %{phone: contact.phone},
          organization_id: contact.organization_id,
          body: body
        },
        :text
      )

    {:reply, :ok, socket}
  end

  def handle_in("update_name", %{"name" => name}, socket) do
    case Contacts.update_contact(socket.assigns.current_contact, %{name: name}) do
      {:ok, contact} ->
        {:reply, :ok, assign(socket, :current_contact, contact)}

      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset_errors(changeset)}}, socket}
    end
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
