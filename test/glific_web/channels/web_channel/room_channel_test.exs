defmodule GlificWeb.WebChannel.RoomChannelTest do
  @moduledoc false
  use GlificWeb.ChannelCase

  alias Glific.{
    Contacts.Location,
    Fixtures,
    GcsFixtures,
    Messages.Message,
    Repo,
    WebChannelFixtures
  }

  alias GlificWeb.WebChannel.{Presence, RoomChannel, Token}

  setup do
    contact = Fixtures.contact_fixture()
    other_contact = Fixtures.contact_fixture()
    %{contact: contact, other_contact: other_contact}
  end

  describe "join/3" do
    test "a contact may join its own topic and gets its message history", %{contact: contact} do
      with_web_channel_enabled(fn ->
        Fixtures.message_fixture(%{
          sender_id: contact.id,
          contact_id: contact.id,
          receiver_id: Glific.Partners.organization_contact_id(contact.organization_id),
          flow: :inbound,
          channel: :web,
          body: "earlier message"
        })

        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)

        assert {:ok, %{messages: messages}, _socket} =
                 WebChannelFixtures.join_web_channel(ws_socket, contact)

        assert Enum.any?(messages, &(&1.body == "earlier message"))
      end)
    end

    test "joining marks the contact online, and leaving marks them offline", %{contact: contact} do
      with_web_channel_enabled(fn ->
        refute Presence.online?(contact.organization_id, contact.id)

        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        assert Presence.online?(contact.organization_id, contact.id)
        assert contact.id in Presence.online_contact_ids(contact.organization_id)

        # Tracked against the channel process, so it is released when the browser goes away
        # rather than needing an explicit "I am leaving" message that a closed laptop never sends.
        leave_and_wait(socket)

        refute Presence.online?(contact.organization_id, contact.id)
      end)
    end

    # Presence is a display nicety, and this is the failure it caused in practice: Phoenix's dev
    # reloader recompiles modules without restarting the supervision tree, so pulling this branch
    # into a running server gave you the code that calls the tracker without the tracker, and an
    # unguarded track/4 raised inside join/3 and took the whole conversation down. Driven against
    # the real thing — the supervised child is stopped, not mocked.
    test "a conversation still opens when the presence tracker is not running", %{
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        without_presence(fn ->
          {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)

          assert {:ok, %{messages: _messages}, _socket} =
                   WebChannelFixtures.join_web_channel(ws_socket, contact)

          # And the two read paths degrade to their empty answer rather than raising: `online?/2`
          # is resolved from a GraphQL field, where a raise would 500 the contact query.
          refute Presence.online?(contact.organization_id, contact.id)
          assert Presence.online_contact_ids(contact.organization_id) == []
        end)
      end)
    end

    test "one contact being online says nothing about another", %{
      contact: contact,
      other_contact: other_contact
    } do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, _socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        assert Presence.online?(contact.organization_id, contact.id)
        refute Presence.online?(other_contact.organization_id, other_contact.id)
      end)
    end

    test "a contact cannot join another contact's topic", %{
      contact: contact,
      other_contact: other_contact
    } do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)

        assert {:error, %{reason: "unauthorized"}} =
                 subscribe_and_join(ws_socket, RoomChannel, "web_channel:#{other_contact.id}")
      end)
    end

    # The sweep only starts at join, so without this check a token that died while the socket
    # idled still buys a join and the history replay with it.
    test "a socket whose token has since expired cannot join", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)

        expired_socket =
          Phoenix.Socket.assign(ws_socket, :token_exp, System.system_time(:second) - 3_600)

        assert {:error, %{reason: "unauthorized"}} =
                 WebChannelFixtures.join_web_channel(expired_socket, contact)
      end)
    end
  end

  describe "load_more" do
    test "returns an older page of the same contact's messages", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "load_more", %{"offset" => 0})
        assert_reply ref, :ok, %{messages: []}
      end)
    end

    # A negative or non-integer offset reaches Ecto's offset and crashes the channel, so it must
    # be rejected before the query rather than raised through it.
    test "rejects an invalid offset instead of crashing the channel", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        for bad_offset <- [-1, "abc", 1.5, nil] do
          ref = push(socket, "load_more", %{"offset" => bad_offset})
          assert_reply ref, :error, %{reason: "invalid_offset"}
        end
      end)
    end
  end

  describe "new_message" do
    test "persists a text message and replies :ok", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_message", %{"body" => "hello there"})
        assert_reply ref, :ok

        assert message = Repo.get_by(Message, contact_id: contact.id, channel: :web)
        assert message.body == "hello there"
        assert message.flow == :inbound
        assert message.sender_id == contact.id

        assert message.receiver_id ==
                 Glific.Partners.organization_contact_id(contact.organization_id)
      end)
    end

    test "rejects a blank body without persisting anything", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_message", %{"body" => "   "})
        assert_reply ref, :error, %{reason: "blank_body"}
        refute Repo.get_by(Message, contact_id: contact.id, channel: :web)
      end)
    end

    test "rejects a body over the length cap", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        too_long = String.duplicate("a", 4_097)
        ref = push(socket, "new_message", %{"body" => too_long})
        assert_reply ref, :error, %{reason: "body_too_long"}
      end)
    end

    test "is rate limited per contact", %{contact: contact} do
      with_web_channel_enabled(fn ->
        rate_limit_key = "web_channel_message:#{contact.id}"
        original_config = Application.get_env(:glific, :web_channel_message_rate_limit)
        Application.put_env(:glific, :web_channel_message_rate_limit, scale_ms: 10_000, count: 1)
        ExRated.delete_bucket(rate_limit_key)

        try do
          {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
          {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

          ref = push(socket, "new_message", %{"body" => "first"})
          assert_reply ref, :ok

          ref = push(socket, "new_message", %{"body" => "second"})
          assert_reply ref, :error, %{reason: "rate_limited"}
        after
          Application.put_env(:glific, :web_channel_message_rate_limit, original_config)
          ExRated.delete_bucket(rate_limit_key)
        end
      end)
    end
  end

  describe "new_media_message" do
    test "accepts a URL this server itself issued", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        url = "#{GlificWeb.Endpoint.url()}/uploads/#{contact.organization_id}/test.png"

        ref =
          push(socket, "new_media_message", %{
            "type" => "image",
            "url" => url,
            "content_type" => "image/png",
            "caption" => "a photo"
          })

        assert_reply ref, :ok

        assert message = Repo.get_by(Message, contact_id: contact.id, type: :image)
        message = Repo.preload(message, :media)
        assert message.media.url == url
      end)
    end

    test "rejects a URL this server did not issue", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref =
          push(socket, "new_media_message", %{
            "type" => "image",
            "url" => "https://evil.example.com/whatever.png"
          })

        assert_reply ref, :error, %{reason: "invalid_media_url"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :image)
      end)
    end

    test "rejects a URL on the right host but another organisation's upload path", %{
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        # Same host the server itself serves local uploads from, but under a directory that
        # belongs to a different organisation than this contact's.
        foreign_org_path =
          "#{GlificWeb.Endpoint.url()}/uploads/#{contact.organization_id + 1}/whatever.png"

        ref =
          push(socket, "new_media_message", %{"type" => "image", "url" => foreign_org_path})

        assert_reply ref, :error, %{reason: "invalid_media_url"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :image)
      end)
    end

    test "rejects an unsupported media type", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_media_message", %{"type" => "sticker", "url" => "whatever"})
        assert_reply ref, :error, %{reason: "unsupported media type"}
      end)
    end
  end

  # A signed PUT URL cannot bind size or content type, so these cover the check against the
  # object's real metadata — not `issued_url?/2`'s shape-only validation.
  describe "new_media_message — GCS object verification" do
    setup %{contact: contact} do
      bucket = "org-#{contact.organization_id}-bucket"
      {private_key_pem, _public_key} = GcsFixtures.generate_rsa_keypair()

      GcsFixtures.create_gcs_credential(
        contact.organization_id,
        bucket,
        "org-#{contact.organization_id}@example.iam.gserviceaccount.com",
        private_key_pem
      )

      %{bucket: bucket, url: "https://storage.googleapis.com/#{bucket}/some-object.png"}
    end

    test "accepts a GCS object whose real metadata matches what was claimed", %{
      contact: contact,
      url: url
    } do
      with_web_channel_enabled(fn ->
        Tesla.Mock.mock_global(fn %{method: :head} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-length", "1024"}, {"content-type", "image/png"}]
          }
        end)

        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref =
          push(socket, "new_media_message", %{
            "type" => "image",
            "url" => url,
            "content_type" => "image/png"
          })

        assert_reply ref, :ok
        assert Repo.get_by(Message, contact_id: contact.id, type: :image)
      end)
    end

    test "rejects a GCS object whose real content type contradicts what was claimed", %{
      contact: contact,
      url: url
    } do
      with_web_channel_enabled(fn ->
        Tesla.Mock.mock_global(fn %{method: :head} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-length", "1024"}, {"content-type", "image/gif"}]
          }
        end)

        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref =
          push(socket, "new_media_message", %{
            "type" => "image",
            "url" => url,
            "content_type" => "image/png"
          })

        assert_reply ref, :error, %{reason: "invalid_media_url"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :image)
      end)
    end

    test "rejects a GCS object over the type's size limit", %{contact: contact, url: url} do
      with_web_channel_enabled(fn ->
        # media_size_limit("image") is 5120 KB; one byte over that in bytes.
        oversized_bytes = 5_120 * 1024 + 1

        Tesla.Mock.mock_global(fn %{method: :head} ->
          %Tesla.Env{
            status: 200,
            headers: [
              {"content-length", to_string(oversized_bytes)},
              {"content-type", "image/png"}
            ]
          }
        end)

        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref =
          push(socket, "new_media_message", %{
            "type" => "image",
            "url" => url,
            "content_type" => "image/png"
          })

        assert_reply ref, :error, %{reason: "media_too_large"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :image)
      end)
    end

    test "rejects a GCS object that no longer exists", %{contact: contact, url: url} do
      with_web_channel_enabled(fn ->
        Tesla.Mock.mock_global(fn %{method: :head} -> %Tesla.Env{status: 404, headers: []} end)

        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref =
          push(socket, "new_media_message", %{
            "type" => "image",
            "url" => url,
            "content_type" => "image/png"
          })

        assert_reply ref, :error, %{reason: "invalid_media_url"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :image)
      end)
    end
  end

  describe "new_location_message" do
    test "persists a location message and the locations row", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_location_message", %{"latitude" => 12.34, "longitude" => 56.78})
        assert_reply ref, :ok

        message = Repo.get_by(Message, contact_id: contact.id, type: :location)
        assert message
        location = Repo.get_by!(Location, message_id: message.id)
        assert location.latitude == 12.34
        assert location.longitude == 56.78
      end)
    end

    test "rejects a string latitude rather than reaching the database", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_location_message", %{"latitude" => "12.34", "longitude" => 56.78})
        assert_reply ref, :error, %{reason: "invalid_location"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :location)
      end)
    end

    test "rejects an out-of-range latitude", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_location_message", %{"latitude" => 200, "longitude" => 56.78})
        assert_reply ref, :error, %{reason: "invalid_location"}
      end)
    end

    test "rejects an out-of-range longitude", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "new_location_message", %{"latitude" => 12.34, "longitude" => -200})
        assert_reply ref, :error, %{reason: "invalid_location"}
        refute Repo.get_by(Message, contact_id: contact.id, type: :location)
      end)
    end
  end

  describe "renew_token" do
    test "extends the session and keeps speaking for the same contact", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        {:ok, renewed, _payload} =
          contact |> Token.sign_contact_token() |> Token.renew_contact_token()

        ref = push(socket, "renew_token", %{"token" => renewed})
        assert_reply ref, :ok
      end)
    end

    test "a valid token belonging to a different contact is rejected, current_contact unchanged",
         %{contact: contact, other_contact: other_contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        foreign_token = Token.sign_contact_token(other_contact)

        ref = push(socket, "renew_token", %{"token" => foreign_token})
        assert_reply ref, :error, %{reason: "invalid_token"}

        assert :sys.get_state(socket.channel_pid).assigns.current_contact.id == contact.id
      end)
    end

    test "a garbage token is rejected", %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = push(socket, "renew_token", %{"token" => "not-a-token"})
        assert_reply ref, :error, %{reason: "invalid_token"}
      end)
    end

    test "a valid token naming the right contact but a different org is rejected, org unchanged",
         %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        # Same contact id as the real one, but claiming a different org — proves the org
        # comparison itself rejects a swap, independent of the contact_id comparison above.
        foreign_org_token =
          Token.sign_contact_token(%Glific.Contacts.Contact{
            id: contact.id,
            organization_id: contact.organization_id + 1,
            phone: contact.phone
          })

        ref = push(socket, "renew_token", %{"token" => foreign_org_token})
        assert_reply ref, :error, %{reason: "invalid_token"}

        state = :sys.get_state(socket.channel_pid)
        assert state.assigns.current_contact.id == contact.id
        assert state.assigns.organization_id == contact.organization_id
      end)
    end
  end

  describe "the mid-session sweep" do
    test "pushes token_expiring once within the warning window, then session_expired past grace",
         %{contact: contact} do
      with_web_channel_enabled(fn ->
        {:ok, ws_socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        now = System.system_time(:second)

        :sys.replace_state(socket.channel_pid, fn s -> put_in(s.assigns.token_exp, now - 30) end)
        send(socket.channel_pid, :sweep_token)
        assert_push "token_expiring", %{}

        # Pushed once: a second sweep at the same age must not push it again.
        send(socket.channel_pid, :sweep_token)
        refute_push "token_expiring", %{}

        ref = Process.monitor(socket.channel_pid)
        :sys.replace_state(socket.channel_pid, fn s -> put_in(s.assigns.token_exp, now - 61) end)
        send(socket.channel_pid, :sweep_token)
        assert_push "session_expired", %{}
        assert_receive {:DOWN, ^ref, :process, _, :normal}
      end)
    end
  end

  # The same three properties, driven by a genuinely minted token rather than the channel's
  # assigns, so these also prove `token_exp` is assigned from a real payload.
  describe "the mid-session sweep, driven by a minted token" do
    test "pushes token_expiring once for a token nearing its own expiry", %{contact: contact} do
      with_web_channel_enabled(fn ->
        near_expiry =
          contact
          |> WebChannelFixtures.web_channel_claims(%{"exp" => System.system_time(:second) + 300})
          |> WebChannelFixtures.sign_web_channel_claims()

        {:ok, ws_socket} =
          WebChannelFixtures.web_channel_socket_fixture(contact, token: near_expiry)

        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        send(socket.channel_pid, :sweep_token)
        assert_push "token_expiring", %{}

        send(socket.channel_pid, :sweep_token)
        refute_push "token_expiring", %{}
      end)
    end

    test "renewing resets the once-only warning, so a still-soon-to-expire renewal warns again",
         %{contact: contact} do
      with_web_channel_enabled(fn ->
        near_expiry =
          contact
          |> WebChannelFixtures.web_channel_claims(%{"exp" => System.system_time(:second) + 300})
          |> WebChannelFixtures.sign_web_channel_claims()

        {:ok, ws_socket} =
          WebChannelFixtures.web_channel_socket_fixture(contact, token: near_expiry)

        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        send(socket.channel_pid, :sweep_token)
        assert_push "token_expiring", %{}

        # Renews to a token itself still inside the warning window, so a second push can only
        # be explained by the renewal having cleared the once-only flag.
        still_near_expiry =
          contact
          |> WebChannelFixtures.web_channel_claims(%{"exp" => System.system_time(:second) + 250})
          |> WebChannelFixtures.sign_web_channel_claims()

        ref = push(socket, "renew_token", %{"token" => still_near_expiry})
        assert_reply ref, :ok

        send(socket.channel_pid, :sweep_token)
        assert_push "token_expiring", %{}
      end)
    end

    test "renewing to a fresh token averts the session_expired the original token's grace would have produced",
         %{contact: contact} do
      with_web_channel_enabled(fn ->
        now = System.system_time(:second)

        about_to_grace_out =
          contact
          |> WebChannelFixtures.web_channel_claims(%{"exp" => now - 55})
          |> WebChannelFixtures.sign_web_channel_claims()

        {:ok, ws_socket} =
          WebChannelFixtures.web_channel_socket_fixture(contact, token: about_to_grace_out)

        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        fresh_token = Token.sign_contact_token(contact)
        ref = push(socket, "renew_token", %{"token" => fresh_token})
        assert_reply ref, :ok

        # The same wait the sibling "not renewing" test uses: unextended, this sweep would stop
        # the channel exactly as that test shows.
        Process.sleep(7_000)

        send(socket.channel_pid, :sweep_token)
        refute_push "session_expired", %{}
        refute_push "token_expiring", %{}

        ref = push(socket, "load_more", %{"offset" => 0})
        assert_reply ref, :ok, %{messages: _messages}
      end)
    end

    test "not renewing a token past its grace period produces session_expired and stops the channel",
         %{contact: contact} do
      with_web_channel_enabled(fn ->
        now = System.system_time(:second)

        # Inside Token's 60s leeway so it still connects, but old enough that grace expires 5s
        # out — a short real wait, no faked time.
        about_to_grace_out =
          contact
          |> WebChannelFixtures.web_channel_claims(%{"exp" => now - 55})
          |> WebChannelFixtures.sign_web_channel_claims()

        {:ok, ws_socket} =
          WebChannelFixtures.web_channel_socket_fixture(contact, token: about_to_grace_out)

        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket, contact)

        ref = Process.monitor(socket.channel_pid)
        Process.sleep(7_000)

        send(socket.channel_pid, :sweep_token)
        assert_push "session_expired", %{}
        assert_receive {:DOWN, ^ref, :process, _, :normal}
      end)
    end
  end

  # Stops the supervised tracker for the duration of `fun` and puts it back whatever happens —
  # leaving it down would break every later test in this file, and the GraphQL contact field that
  # reads it.
  @spec without_presence((-> any())) :: any()
  defp without_presence(fun) do
    :ok = Supervisor.terminate_child(Glific.Supervisor, Presence)

    try do
      fun.()
    after
      {:ok, _pid} = Supervisor.restart_child(Glific.Supervisor, Presence)
    end
  end

  # Presence untracks on process exit, which is asynchronous — polling here rather than asserting
  # straight after leave/1 keeps the test from racing the Presence server.
  @spec leave_and_wait(Phoenix.Socket.t()) :: :ok
  defp leave_and_wait(socket) do
    channel_pid = socket.channel_pid
    reference = Process.monitor(channel_pid)
    Process.unlink(channel_pid)
    :ok = close(socket)

    receive do
      {:DOWN, ^reference, :process, ^channel_pid, _reason} -> :ok
    after
      1_000 -> flunk("the channel process did not shut down")
    end

    Process.sleep(50)
    :ok
  end
end
