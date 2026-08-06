defmodule GlificWeb.WebChannel.RoomChannel do
  @moduledoc """
  The Phoenix channel a browser contact joins to hold its own web channel conversation:
  fetching recent history, sending/receiving messages live, and updating its display name.

  Topic shape: `"web_channel:<contact_id>"` — a contact may only join its own topic (enforced
  in `join/3` against `socket.assigns.current_contact`, set during `GlificWeb.WebChannelSocket`
  authentication).
  """

  use GlificWeb, :channel

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Contacts.ContactsField,
    Flows.ContactField,
    Messages,
    Repo
  }

  alias GlificWeb.WebChannel.DisplayName
  alias GlificWeb.WebChannel.MessageSerializer
  alias GlificWeb.WebChannel.Presence

  @page_size 100

  # Intercept outbound "new_message" broadcasts so we can piggyback a live display-name sync on
  # them (see handle_out/3). A flow runs asynchronously (Communications.Message.process_message/1
  # hands off to a poolboy worker), so the name it captures isn't committed when the inbound
  # handler returns — but it IS committed by the time the flow's reply is delivered here.
  intercept(["new_message"])

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

      # Seed the last-known display name so a later flow-driven change (e.g. the newcontact flow
      # capturing @contact.fields.name) can be detected and pushed live — see maybe_push_display_name/1.
      socket = assign(socket, :display_name, DisplayName.resolve(socket.assigns.current_contact))

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
  # real ConsumerWorker does not. process_message/1 captures self() (this channel process) as the
  # caller, so the mock's notification lands here; swallow it rather than crash.
  def handle_info(:received_message_to_process, socket), do: {:noreply, socket}

  @impl true
  @spec handle_out(String.t(), map(), Phoenix.Socket.t()) :: {:noreply, Phoenix.Socket.t()}
  def handle_out("new_message", payload, socket) do
    # Forward the outbound message to the browser (the default behaviour we replaced by
    # intercepting), then re-check the display name: a flow that just replied may have captured
    # @contact.fields.name, and its write is committed by now. See maybe_push_display_name/1.
    push(socket, "new_message", payload)
    {:noreply, maybe_push_display_name(socket)}
  end

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

  # The file was already uploaded to storage via POST /api/v1/web_channel/upload, so the payload
  # carries only the resulting url — no file bytes travel over the socket. `type` selects the
  # message type (and thus which flow case, e.g. has_audio/has_media, fires).
  def handle_in("new_media_message", %{"type" => type, "url" => url} = params, socket)
      when type in ~w(image audio video document) do
    contact = socket.assigns.current_contact
    caption = params["caption"]

    :ok =
      WebMessage.receive_message(
        %{
          sender: %{phone: contact.phone},
          organization_id: contact.organization_id,
          url: url,
          source_url: url,
          caption: caption,
          content_type: params["content_type"],
          body: caption || ""
        },
        String.to_existing_atom(type)
      )

    {:reply, :ok, socket}
  end

  def handle_in("new_media_message", _params, socket),
    do: {:reply, {:error, %{reason: "unsupported media type"}}, socket}

  def handle_in("new_location_message", %{"latitude" => lat, "longitude" => lng}, socket) do
    contact = socket.assigns.current_contact

    :ok =
      WebMessage.receive_message(
        %{
          sender: %{phone: contact.phone},
          organization_id: contact.organization_id,
          longitude: lng,
          latitude: lat,
          body: "https://www.google.com/maps?q=#{lat},#{lng}"
        },
        :location
      )

    {:reply, :ok, socket}
  end

  def handle_in("update_name", %{"name" => name}, socket) when is_binary(name) do
    # This is a public socket event; the widget guards against blanks but a raw client may not.
    # Reject a blank name rather than writing "" into contact.name and contact.fields.name.
    trimmed = String.trim(name)

    if trimmed == "" do
      {:reply, {:error, %{errors: %{name: ["can't be blank"]}}}, socket}
    else
      do_update_name(trimmed, socket)
    end
  end

  def handle_in("update_name", _params, socket),
    do: {:reply, {:error, %{errors: %{name: ["can't be blank"]}}}, socket}

  @spec do_update_name(String.t(), Phoenix.Socket.t()) ::
          {:reply, :ok | {:error, map()}, Phoenix.Socket.t()}
  defp do_update_name(name, socket) do
    case Contacts.update_contact(socket.assigns.current_contact, %{name: name}) do
      {:ok, contact} ->
        # Mirror the rename into contact.fields.name so flows (@contact.fields.name) see it.
        # Gated behind the update_contact success branch: do_add_contact_field/5 raises on a
        # bad changeset, so a rejected name must reply {:error, ...} rather than crash the channel.
        # Reuse the org's existing "name" field label (default "Name") instead of hardcoding it —
        # a hardcoded label would revert an org's renamed field org-wide via ContactField's
        # update_all when this least-privileged surface fires.
        label = name_field_label(contact.organization_id)
        contact = ContactField.do_add_contact_field(contact, "name", label, name, "string")

        # Keep :display_name in step with the rename so a following inbound message doesn't
        # re-detect this as a change and push a redundant contact_updated event.
        socket = socket |> assign(:current_contact, contact) |> assign(:display_name, name)
        {:reply, :ok, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset_errors(changeset)}}, socket}
    end
  end

  # After an inbound message is processed (flow runs synchronously in this channel process), the
  # flow may have written @contact.fields.name — e.g. the newcontact flow capturing the name. Re-
  # read the contact and, if the resolved display name changed since we last told the client, push
  # it live so the widget header updates without a re-login.
  @spec maybe_push_display_name(Phoenix.Socket.t()) :: Phoenix.Socket.t()
  defp maybe_push_display_name(socket) do
    contact = Contacts.get_contact!(socket.assigns.current_contact.id)
    name = DisplayName.resolve(contact)
    socket = assign(socket, :current_contact, contact)

    if name != socket.assigns[:display_name] do
      push(socket, "contact_updated", %{name: name})
      assign(socket, :display_name, name)
    else
      socket
    end
  end

  # Label for the org's "name" contact field, so mirroring a rename into contact.fields.name
  # preserves an org-customized label instead of forcing it back to the default.
  @spec name_field_label(non_neg_integer()) :: String.t()
  defp name_field_label(organization_id) do
    case Repo.get_by(ContactsField, %{shortcode: "name", scope: :contact},
           organization_id: organization_id
         ) do
      %ContactsField{name: label} -> label
      _ -> "Name"
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
