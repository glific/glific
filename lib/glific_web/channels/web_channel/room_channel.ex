defmodule GlificWeb.WebChannel.RoomChannel do
  @moduledoc """
  The Phoenix channel a browser contact joins to hold its own web channel conversation:
  fetching recent history, sending messages, and being swept for token expiry.

  Topic shape: `"web_channel:<contact_id>"` — a contact may only join its own topic (enforced
  in `join/3` against `socket.assigns.current_contact`, set during `GlificWeb.WebChannelSocket`
  authentication). That is the only place topic ownership is checked; `renew_token` below must
  never be allowed to change which contact a joined socket speaks for.
  """

  use GlificWeb, :channel

  alias Glific.{
    Communications.WebMessage,
    GCS.ObjectMetadata,
    Messages,
    Providers.Web.Upload,
    Repo
  }

  alias GlificWeb.WebChannel.{MessageSerializer, Token}

  @page_size 100
  @max_body_length 4_096

  # api-auth-design.md §2.4: the sweep interval is the real granularity, not the token TTL — a
  # token expiring at T dies at T + interval. 60s against the token's 1h TTL is a backstop, not
  # the primary renewal mechanism (the widget renews ten minutes early).
  @sweep_interval_ms 60_000
  # Matches WEB_CHANNEL_TOKEN_REFRESH_THRESHOLD_SECONDS on the widget, so both sides agree on
  # when renewal is due.
  @warning_window_seconds 600
  # Matches Token's own clock leeway — killing at exactly `exp` while the verifier still
  # accepts a 60s-old token would be two components disagreeing.
  @grace_seconds 60

  @impl true
  @spec join(String.t(), map(), Phoenix.Socket.t()) ::
          {:ok, map(), Phoenix.Socket.t()} | {:error, map()}
  def join("web_channel:" <> contact_id, _params, socket) do
    # `connect/3` verified the token once; a client can sit on an authenticated socket without
    # joining until well past `exp` and the sweep would not start until it did. Both refusals
    # answer identically, so a caller cannot tell an expired token from someone else's topic.
    if contact_id == to_string(socket.assigns.current_contact.id) and not token_expired?(socket) do
      # The channel runs in its own process, separate from the connect/3 process, so org
      # context has to be re-established here — same requirement as an Oban worker's perform/1.
      Repo.put_process_state(socket.assigns.organization_id)
      schedule_sweep()

      messages =
        contact_id
        |> String.to_integer()
        |> Messages.list_conversation_messages(:web, %{limit: @page_size, offset: 0})
        |> Enum.reverse()
        |> Enum.map(&MessageSerializer.serialize/1)

      socket = assign(socket, :token_expiring_warned?, false)

      {:ok, %{messages: messages}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  @spec handle_info(:sweep_token, Phoenix.Socket.t()) ::
          {:noreply, Phoenix.Socket.t()} | {:stop, :normal, Phoenix.Socket.t()}
  def handle_info(:sweep_token, socket) do
    now = System.system_time(:second)
    exp = socket.assigns.token_exp

    cond do
      now >= exp + @grace_seconds ->
        push(socket, "session_expired", %{})
        {:stop, :normal, socket}

      now >= exp - @warning_window_seconds and not socket.assigns.token_expiring_warned? ->
        push(socket, "token_expiring", %{})
        schedule_sweep()
        {:noreply, assign(socket, :token_expiring_warned?, true)}

      true ->
        schedule_sweep()
        {:noreply, socket}
    end
  end

  # Glific.Processor.ConsumerWorkerMock (test env only) notifies the caller process once it
  # has "processed" a message — swallow it here rather than crash, since nothing in this
  # ticket hands a message to that consumer in the first place.
  def handle_info(:received_message_to_process, socket), do: {:noreply, socket}

  @impl true
  @spec handle_in(String.t(), map(), Phoenix.Socket.t()) ::
          {:reply, :ok | {:ok, map()} | {:error, map()}, Phoenix.Socket.t()}
  def handle_in("load_more", %{"offset" => offset}, socket) do
    contact_id = socket.assigns.current_contact.id

    messages =
      contact_id
      |> Messages.list_conversation_messages(:web, %{limit: @page_size, offset: offset})
      |> Enum.reverse()
      |> Enum.map(&MessageSerializer.serialize/1)

    {:reply, {:ok, %{messages: messages}}, socket}
  end

  def handle_in("new_message", %{"body" => body}, socket) do
    contact = socket.assigns.current_contact

    # No bsp_message_id here on purpose: the web channel has no BSP, and a client-supplied
    # value under the (bsp_message_id, organization_id) unique index could collide with a
    # real BSP id or suppress another contact's message. Postgres allows many nulls under it.
    with :ok <- check_message_rate_limit(contact.id),
         {:ok, trimmed} <- validate_body(body),
         {:ok, _message} <-
           WebMessage.receive_message(
             %{
               sender: %{phone: contact.phone},
               organization_id: contact.organization_id,
               body: trimmed
             },
             :text
           ) do
      {:reply, :ok, socket}
    else
      error -> {:reply, {:error, %{reason: failure_reason(error)}}, socket}
    end
  end

  def handle_in("new_message", _params, socket),
    do: {:reply, {:error, %{reason: "blank_body"}}, socket}

  # The file was already uploaded straight to GCS via a pre-signed URL from
  # POST /api/v1/web_channel/upload-url, so the payload carries only the resulting url — no
  # file bytes travel over the socket.
  def handle_in("new_media_message", %{"type" => type, "url" => url} = params, socket)
      when type in ~w(image audio video document) do
    contact = socket.assigns.current_contact
    caption = params["caption"]
    content_type = params["content_type"]

    with :ok <- check_message_rate_limit(contact.id),
         true <- Upload.issued_url?(contact.organization_id, url),
         :ok <- verify_uploaded_media(contact.organization_id, type, url, content_type),
         {:ok, _message} <-
           WebMessage.receive_message(
             %{
               sender: %{phone: contact.phone},
               organization_id: contact.organization_id,
               url: url,
               source_url: url,
               caption: caption,
               content_type: content_type,
               body: caption || ""
             },
             String.to_existing_atom(type)
           ) do
      {:reply, :ok, socket}
    else
      false -> {:reply, {:error, %{reason: "invalid_media_url"}}, socket}
      {:error, :media_too_large} -> {:reply, {:error, %{reason: "media_too_large"}}, socket}
      {:error, :invalid_media_url} -> {:reply, {:error, %{reason: "invalid_media_url"}}, socket}
      error -> {:reply, {:error, %{reason: failure_reason(error)}}, socket}
    end
  end

  def handle_in("new_media_message", _params, socket),
    do: {:reply, {:error, %{reason: "unsupported media type"}}, socket}

  def handle_in("new_location_message", %{"latitude" => lat, "longitude" => lng}, socket) do
    contact = socket.assigns.current_contact

    with :ok <- check_message_rate_limit(contact.id),
         true <- valid_coordinate?(lat, -90, 90),
         true <- valid_coordinate?(lng, -180, 180),
         {:ok, _message} <-
           WebMessage.receive_message(
             %{
               sender: %{phone: contact.phone},
               organization_id: contact.organization_id,
               longitude: lng,
               latitude: lat,
               body: "https://www.google.com/maps?q=#{lat},#{lng}"
             },
             :location
           ) do
      {:reply, :ok, socket}
    else
      false -> {:reply, {:error, %{reason: "invalid_location"}}, socket}
      error -> {:reply, {:error, %{reason: failure_reason(error)}}, socket}
    end
  end

  def handle_in("new_location_message", _params, socket),
    do: {:reply, {:error, %{reason: "invalid_location"}}, socket}

  def handle_in("renew_token", %{"token" => token}, socket) do
    with {:ok, payload} <- Token.verify_contact_token(token),
         true <- payload.contact_id == socket.assigns.current_contact.id,
         true <- payload.org_id == socket.assigns.organization_id do
      socket =
        socket
        |> assign(:token_exp, payload.exp)
        |> assign(:token_expiring_warned?, false)

      {:reply, :ok, socket}
    else
      # Collapsed to one reason regardless of cause (bad signature, expired, or — the case that
      # matters here — a token that verifies but belongs to a different contact/org) so a
      # renewal can never be used to probe which. `current_contact` is untouched in every branch.
      _ -> {:reply, {:error, %{reason: "invalid_token"}}, socket}
    end
  end

  def handle_in("renew_token", _params, socket),
    do: {:reply, {:error, %{reason: "invalid_token"}}, socket}

  @spec schedule_sweep() :: reference()
  defp schedule_sweep, do: Process.send_after(self(), :sweep_token, @sweep_interval_ms)

  @spec token_expired?(Phoenix.Socket.t()) :: boolean()
  defp token_expired?(socket),
    do: System.system_time(:second) >= socket.assigns.token_exp + @grace_seconds

  # A persist failure must reply, not raise: a raise takes the channel process down, so the
  # widget sees a socket teardown instead of the error its retry path is built on.
  @spec failure_reason(any()) :: String.t()
  defp failure_reason({:error, reason}) when is_binary(reason), do: reason
  defp failure_reason(_error), do: "send_failed"

  # The declared `size` at signing time only bounds the honest case — a signed PUT URL cannot
  # bind an upload's size or verify its bytes, so this is the authoritative check, run against
  # the object's real metadata rather than a client-supplied claim. Only GCS objects are
  # checked; a local-fallback URL (dev/test only) has no bucket/object to look up.
  #
  # A rejection here leaves the object in the bucket: cleanup is a bucket lifecycle rule's job,
  # not this socket handler's.
  @spec verify_uploaded_media(non_neg_integer(), String.t(), String.t(), String.t() | nil) ::
          :ok | {:error, :media_too_large | :invalid_media_url}
  defp verify_uploaded_media(organization_id, type, url, claimed_content_type) do
    case Upload.gcs_object(organization_id, url) do
      {:ok, bucket, object_name} ->
        case ObjectMetadata.fetch(organization_id, bucket, object_name) do
          {:ok, metadata} -> validate_uploaded_metadata(type, metadata, claimed_content_type)
          _ -> {:error, :invalid_media_url}
        end

      :error ->
        :ok
    end
  end

  @spec validate_uploaded_metadata(String.t(), map(), String.t() | nil) ::
          :ok | {:error, :media_too_large | :invalid_media_url}
  defp validate_uploaded_metadata(type, %{size: size_bytes, content_type: content_type}, claimed) do
    limit_kb = Messages.media_size_limit(type)

    cond do
      content_type != claimed -> {:error, :invalid_media_url}
      !Messages.valid_media_content_type?(type, content_type) -> {:error, :invalid_media_url}
      is_nil(limit_kb) -> {:error, :invalid_media_url}
      size_bytes / 1024 > limit_kb -> {:error, :media_too_large}
      true -> :ok
    end
  end

  @spec check_message_rate_limit(non_neg_integer()) :: :ok | {:error, String.t()}
  defp check_message_rate_limit(contact_id) do
    config = Application.get_env(:glific, :web_channel_message_rate_limit, [])
    scale_ms = Keyword.get(config, :scale_ms, 10_000)
    count = Keyword.get(config, :count, 20)

    case ExRated.check_rate("web_channel_message:#{contact_id}", scale_ms, count) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, "rate_limited"}
    end
  end

  @spec validate_body(any()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_body(body) when is_binary(body) do
    trimmed = String.trim(body)

    cond do
      trimmed == "" -> {:error, "blank_body"}
      String.length(trimmed) > @max_body_length -> {:error, "body_too_long"}
      true -> {:ok, trimmed}
    end
  end

  defp validate_body(_body), do: {:error, "blank_body"}

  @spec valid_coordinate?(any(), number(), number()) :: boolean()
  defp valid_coordinate?(value, min, max) when is_number(value), do: value >= min and value <= max
  defp valid_coordinate?(_value, _min, _max), do: false
end
