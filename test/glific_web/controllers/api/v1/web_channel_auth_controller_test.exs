defmodule GlificWeb.API.V1.WebChannelAuthControllerTest do
  @moduledoc false

  # Not async: this file flips the global `web_channel_enabled` FunWithFlags flag and reads/writes
  # `PasswordlessAuth`'s global OTP store, both of which are shared process/ETS state.
  use GlificWeb.ConnCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    OTP,
    Partners,
    Repo,
    Seeds.SeedsDev,
    Templates.SessionTemplate,
    Users
  }

  alias GlificWeb.WebChannel.Token

  # Seeded by `SeedsDev.seed_contacts/1` with `bsp_status: :session_and_hsm` and a recent
  # `optin_time`/`last_message_at`, so it is deliverable via a session message without any extra
  # setup — this is our stand-in for "a reachable contact".
  @reachable_phone "917834811231"

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    Fixtures.set_bsp_partner_tokens()
    Fixtures.otp_hsm_fixture()

    # Broad catch-all so the (synchronous) BSP send triggered by a successful OTP dispatch never
    # makes a real network call, whichever of the session/HSM paths `Messages.
    # create_and_send_otp_verification_message/2` picks.
    Tesla.Mock.mock(fn %{method: :post} ->
      %Tesla.Env{
        status: 200,
        body: Jason.encode!(%{"status" => "submitted", "messageId" => Ecto.UUID.generate()})
      }
    end)

    :ok
  end

  # Generates a fresh, E.164-parseable Indian phone number so tests never collide with each other
  # or with the seeded fixtures, and never need a lookup against `Contacts.parse_phone_number/1`
  # to fail from an accidentally-invalid Faker-generated number.
  @spec unique_phone() :: String.t()
  defp unique_phone do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.pad_leading(9, "0")

    "919" <> suffix
  end

  # `FunWithFlags.enable/disable/2` writes through to Postgres, so it must run on the same
  # process that owns the SQL sandbox connection for this test — an `on_exit` callback runs in a
  # *different* process, after the test process (and with it, sandbox ownership) has already
  # exited, so `FunWithFlags.disable/2` there raises a `DBConnection` ownership error (confirmed
  # empirically; see the same constraint documented in `test/glific/ai_test.exs`). `try/after`
  # inside the test process itself is the only reliable way to flip the flag back off — including
  # when an assertion inside `fun` fails — before this test's connection goes away, so a later
  # test file (e.g. `organization_test.exs`, which asserts `web_channel_enabled == false` for
  # org 1) never observes it stuck on.
  @spec with_web_channel_enabled((-> any())) :: any()
  defp with_web_channel_enabled(fun) do
    FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: 1})
    Partners.organization(1) |> Partners.fill_cache()

    try do
      fun.()
    after
      FunWithFlags.disable(:web_channel_enabled, for_actor: %{organization_id: 1})
      Partners.organization(1) |> Partners.fill_cache()
    end
  end

  describe "renew_token/2" do
    setup %{conn: conn} do
      # A real login, so the token under test is one the system actually issued.
      %{conn: conn, phone: @reachable_phone}
    end

    defp sign_in(conn, phone) do
      code = OTP.generate_code(:web_channel, phone)

      conn
      |> post(
        Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{"phone" => phone, "otp" => code})
      )
      |> json_response(200)
      |> get_in(["data", "token"])
    end

    test "exchanges a valid token for a fresh one", %{conn: conn, phone: phone} do
      with_web_channel_enabled(fn ->
        token = sign_in(conn, phone)

        renew_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :renew_token, %{"token" => token})
          )

        assert json = json_response(renew_conn, 200)
        renewed = get_in(json, ["data", "token"])

        assert is_binary(renewed)
        assert {:ok, payload} = Token.verify_contact_token(renewed)
        assert payload.org_id == 1

        # Same response shape as verify-otp, so the widget can store it with the same code path.
        assert get_in(json, ["data", "contact_id"]) == payload.contact_id
        assert get_in(json, ["data", "phone"]) == phone
        assert Map.has_key?(json["data"], "name")
      end)
    end

    test "the renewed token belongs to the same session", %{conn: conn, phone: phone} do
      with_web_channel_enabled(fn ->
        token = sign_in(conn, phone)
        {:ok, before} = Token.verify_contact_token(token)

        renewed =
          conn
          |> post(Routes.api_v1_web_channel_auth_path(conn, :renew_token, %{"token" => token}))
          |> json_response(200)
          |> get_in(["data", "token"])

        {:ok, after_renewal} = Token.verify_contact_token(renewed)
        assert after_renewal.session_id == before.session_id
        assert after_renewal.session_started_at == before.session_started_at
      end)
    end

    test "rejects a garbage token with 401", %{conn: conn} do
      with_web_channel_enabled(fn ->
        renew_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :renew_token, %{"token" => "not-a-token"})
          )

        assert json = json_response(renew_conn, 401)
        assert get_in(json, ["error", "message"]) == "Invalid or expired session"
      end)
    end

    test "rejects an OTP code presented as a token", %{conn: conn, phone: phone} do
      with_web_channel_enabled(fn ->
        code = OTP.generate_code(:web_channel, phone)

        renew_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :renew_token, %{"token" => code})
          )

        assert json_response(renew_conn, 401)
      end)
    end

    test "a missing or blank token is a 422, not a 401", %{conn: conn} do
      with_web_channel_enabled(fn ->
        for params <- [%{}, %{"token" => ""}] do
          renew_conn =
            post(conn, Routes.api_v1_web_channel_auth_path(conn, :renew_token, params))

          assert json = json_response(renew_conn, 422)
          assert get_in(json, ["error", "message"]) == "Token is required"
        end
      end)
    end

    test "refuses a token whose organization is not the one the request resolved to", %{
      conn: conn,
      phone: phone
    } do
      with_web_channel_enabled(fn ->
        # Deliberately names a contact that DOES exist in org 1 while claiming org 2. A token
        # naming some arbitrary foreign contact id would be caught by the org-scoped contact
        # lookup instead, and would prove nothing about this check — contact ids come from one
        # global sequence, so they never collide across orgs and the lookup would always save us.
        # Isolating the check means making the lookup succeed.
        existing = Repo.get_by!(Contact, phone: phone)

        foreign =
          Token.sign_contact_token(%Contact{
            id: existing.id,
            organization_id: 2,
            phone: phone
          })

        assert {:ok, %{org_id: 2, contact_id: contact_id}} = Token.verify_contact_token(foreign)
        assert contact_id == existing.id

        # The signing key is installation-wide today (#5711 makes it per-org), so this token is
        # cryptographically valid here. Only the explicit org comparison rejects it.
        renew_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :renew_token, %{"token" => foreign})
          )

        assert json = json_response(renew_conn, 401)
        assert get_in(json, ["error", "message"]) == "Invalid or expired session"
      end)
    end

    test "returns 404 when the web channel is off", %{conn: conn} do
      renew_conn =
        post(
          conn,
          Routes.api_v1_web_channel_auth_path(conn, :renew_token, %{"token" => "anything"})
        )

      assert json = json_response(renew_conn, 404)

      assert get_in(json, ["error", "message"]) ==
               "Web channel is not enabled for this organization"
    end
  end

  describe "feature flag" do
    test "request-otp returns 404 when web_channel_enabled is off (the ConnCase default)", %{
      conn: conn
    } do
      conn =
        post(
          conn,
          Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{"phone" => @reachable_phone})
        )

      assert json = json_response(conn, 404)

      assert get_in(json, ["error", "message"]) ==
               "Web channel is not enabled for this organization"
    end

    test "verify-otp returns 404 when web_channel_enabled is off (the ConnCase default)", %{
      conn: conn
    } do
      conn =
        post(
          conn,
          Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
            "phone" => @reachable_phone,
            "otp" => "123456"
          })
        )

      assert json = json_response(conn, 404)

      assert get_in(json, ["error", "message"]) ==
               "Web channel is not enabled for this organization"
    end

    test "takes effect without refilling the organization cache", %{conn: conn} do
      # The regression this pins: an admin enables the flag and nothing else happens. Nobody
      # calls Partners.fill_cache/1, so `organization.web_channel_enabled` — a virtual field
      # stamped on only while that function runs — keeps reporting the value it had when the
      # cache was last filled. A controller reading it answers 404 indefinitely.
      #
      # Deliberately NOT using with_web_channel_enabled/1 here: that helper refills the cache,
      # which is exactly the step being asserted as unnecessary.
      Partners.organization(1) |> Partners.fill_cache()
      assert Partners.organization(1).web_channel_enabled == false

      FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: 1})

      try do
        # The stale snapshot is still sitting in the cache, and that is the point.
        assert Partners.organization(1).web_channel_enabled == false

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json = json_response(conn, 200)

        assert get_in(json, ["data", "message"]) ==
                 "If this number is registered on WhatsApp, you will receive a one-time code"
      after
        FunWithFlags.disable(:web_channel_enabled, for_actor: %{organization_id: 1})
        Partners.organization(1) |> Partners.fill_cache()
      end
    end

    test "both endpoints behave normally once web_channel_enabled is turned on", %{conn: conn} do
      with_web_channel_enabled(fn ->
        request_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json_response(request_conn, 200)

        verify_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => @reachable_phone,
              "otp" => "wrong_otp"
            })
          )

        # 401, not 404 — the flag no longer gates this request once it is on.
        assert json_response(verify_conn, 401)
      end)
    end
  end

  describe "request_otp/2" do
    test "a valid phone for a reachable contact returns the neutral message and sends a message",
         %{conn: conn} do
      with_web_channel_enabled(fn ->
        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json = json_response(conn, 200)
        assert get_in(json, ["data", "phone"]) == @reachable_phone

        assert get_in(json, ["data", "message"]) ==
                 "If this number is registered on WhatsApp, you will receive a one-time code"

        contact = Repo.get_by!(Contact, phone: @reachable_phone)

        assert Repo.exists?(
                 from(m in Glific.Messages.Message, where: m.receiver_id == ^contact.id)
               )
      end)
    end

    test "a phone that has never been seen returns a byte-identical response", %{conn: conn} do
      with_web_channel_enabled(fn ->
        known_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        known_json = json_response(known_conn, 200)

        never_seen_phone = unique_phone()

        unknown_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => never_seen_phone
            })
          )

        unknown_json = json_response(unknown_conn, 200)

        # Identical apart from the echoed phone — this is the enumeration-protection criterion:
        # an attacker cannot tell a known contact from a number that has never been seen.
        assert Map.delete(known_json["data"], "phone") ==
                 Map.delete(unknown_json["data"], "phone")

        assert unknown_json["data"]["phone"] == never_seen_phone
      end)
    end

    test "an undeliverable contact still returns the identical neutral response", %{conn: conn} do
      with_web_channel_enabled(fn ->
        reachable_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        reachable_json = json_response(reachable_conn, 200)

        # The status has to be :blocked, not :invalid. `send_web_channel_otp/2` opts the contact
        # in *before* checking deliverability, and `Contacts.contact_opted_in/4` forces
        # `status: :valid` on the way through — `ignore_optin?/2` (contacts.ex:551-559) only
        # declines to do that for a :blocked contact. With :invalid the fixture is quietly
        # flipped to :valid and this test would exercise the success path while claiming
        # otherwise. :blocked survives the opt-in, fails `can_send_message_to?/1`, and so
        # actually reaches the failure branch this test exists to cover.
        undeliverable = Fixtures.contact_fixture(%{status: :blocked, phone: unique_phone()})

        undeliverable_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => undeliverable.phone
            })
          )

        undeliverable_json = json_response(undeliverable_conn, 200)

        assert Map.delete(reachable_json["data"], "phone") ==
                 Map.delete(undeliverable_json["data"], "phone")

        assert undeliverable_json["data"]["phone"] == undeliverable.phone

        # Proves the response above really is the failure branch and not the success path
        # wearing its clothes: nothing was sent, so no message row exists for this contact.
        refute Repo.exists?(
                 from(m in Glific.Messages.Message, where: m.receiver_id == ^undeliverable.id)
               )
      end)
    end

    test "an organization with no verify_otp HSM template still returns the neutral response", %{
      conn: conn
    } do
      with_web_channel_enabled(fn ->
        # A contact that is outside the 24-hour session window but is opted in, so
        # `Messages.create_and_send_otp_verification_message/2` takes the HSM-template branch
        # rather than the session-message one.
        # last_message_at must be older than 24 hours. `contact_opted_in/4` re-derives bsp_status
        # via `set_session_status(contact, :hsm)` (contacts.ex:768-775), which promotes to
        # :session_and_hsm whenever the last message is inside the window — and a
        # :session_and_hsm contact takes the plain-session branch, never the template one.
        hsm_only =
          Fixtures.contact_fixture(%{
            phone: unique_phone(),
            bsp_status: :hsm,
            optin_time: DateTime.utc_now() |> DateTime.truncate(:second),
            optin_status: true,
            last_message_at: Glific.go_back_time(48)
          })

        # Remove the template that branch hard-matches on. This is the shape of a real pilot-org
        # misconfiguration: the flag gets switched on before the `verify_otp` HSM is approved.
        {:ok, _} =
          SessionTemplate
          |> Repo.get_by!(shortcode: "verify_otp", organization_id: 1)
          |> Repo.delete()

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{"phone" => hsm_only.phone})
          )

        # The template lookup raises rather than returning {:error, _}. Without the rescue in
        # `send_web_channel_otp/2` this is a 500, which would both break the always-200 contract
        # and hand a caller a way to tell a deliverable number from an undeliverable one.
        assert json = json_response(conn, 200)

        assert get_in(json, ["data", "message"]) ==
                 "If this number is registered on WhatsApp, you will receive a one-time code"

        refute Repo.exists?(
                 from(m in Glific.Messages.Message, where: m.receiver_id == ^hsm_only.id)
               )
      end)
    end

    test "missing phone returns 422", %{conn: conn} do
      with_web_channel_enabled(fn ->
        conn = post(conn, Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{}))

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "message"]) == "Phone number is required"
      end)
    end

    test "blank phone returns 422", %{conn: conn} do
      with_web_channel_enabled(fn ->
        conn =
          post(conn, Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{"phone" => ""}))

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "message"]) == "Phone number is required"
      end)
    end

    test "an invalid E.164 phone returns 422 without consulting the rate limiter", %{conn: conn} do
      with_web_channel_enabled(fn ->
        rate_limit_key = "web_channel_send_otp:#{GlificWeb.Tenants.remote_ip(conn)}"
        original_config = Application.get_env(:glific, :web_channel_otp_rate_limit)
        Application.put_env(:glific, :web_channel_otp_rate_limit, scale_ms: 30_000, count: 1)
        ExRated.delete_bucket(rate_limit_key)

        on_exit(fn ->
          Application.put_env(:glific, :web_channel_otp_rate_limit, original_config)
          ExRated.delete_bucket(rate_limit_key)
        end)

        not_a_phone_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{"phone" => "notaphone"})
          )

        assert not_a_phone_json = json_response(not_a_phone_conn, 422)
        assert get_in(not_a_phone_json, ["error", "message"])

        too_short_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{"phone" => "12345"})
          )

        assert too_short_json = json_response(too_short_conn, 422)
        assert get_in(too_short_json, ["error", "message"])

        # Neither invalid attempt above consumed the (count: 1) rate-limit budget: a valid
        # request right after them still succeeds instead of 429ing — proving validation runs
        # before the rate limiter.
        valid_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json_response(valid_conn, 200)
      end)
    end

    test "is rate limited to one request per IP within the window", %{conn: conn} do
      with_web_channel_enabled(fn ->
        rate_limit_key = "web_channel_send_otp:#{GlificWeb.Tenants.remote_ip(conn)}"
        original_config = Application.get_env(:glific, :web_channel_otp_rate_limit)
        Application.put_env(:glific, :web_channel_otp_rate_limit, scale_ms: 30_000, count: 1)
        ExRated.delete_bucket(rate_limit_key)

        on_exit(fn ->
          Application.put_env(:glific, :web_channel_otp_rate_limit, original_config)
          ExRated.delete_bucket(rate_limit_key)
        end)

        first =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json_response(first, 200)

        second =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json = json_response(second, 429)

        assert get_in(json, ["error", "message"]) ==
                 "An OTP was just sent. Please try again in 30 seconds."
      end)
    end

    test "the web channel rate-limit budget is independent of the staff registration budget", %{
      conn: conn
    } do
      with_web_channel_enabled(fn ->
        web_channel_key = "web_channel_send_otp:#{GlificWeb.Tenants.remote_ip(conn)}"
        staff_key = "send_otp:#{GlificWeb.Tenants.remote_ip(conn)}"

        original_web_channel_config = Application.get_env(:glific, :web_channel_otp_rate_limit)
        original_staff_config = Application.get_env(:glific, :otp_rate_limit)

        Application.put_env(:glific, :web_channel_otp_rate_limit, scale_ms: 30_000, count: 1)
        Application.put_env(:glific, :otp_rate_limit, scale_ms: 30_000, count: 1)
        ExRated.delete_bucket(web_channel_key)
        ExRated.delete_bucket(staff_key)

        on_exit(fn ->
          Application.put_env(:glific, :web_channel_otp_rate_limit, original_web_channel_config)
          Application.put_env(:glific, :otp_rate_limit, original_staff_config)
          ExRated.delete_bucket(web_channel_key)
          ExRated.delete_bucket(staff_key)
        end)

        Tesla.Mock.mock(fn
          %{method: :post} ->
            %Tesla.Env{
              body:
                "{\n  \"success\": true,\n  \"challenge_ts\": \"2023-01-09T04:58:39Z\",\n  \"hostname\": \"glific.test\",\n  \"score\": 0.9,\n  \"action\": \"register\"\n}",
              status: 200
            }

          %{method: :get, url: url} = env ->
            if String.contains?(url, "/wallet/balance") do
              %Tesla.Env{
                status: 200,
                body:
                  "{\"status\":\"success\",\"walletResponse\":{\"currency\":\"USD\",\"currentBalance\":1.787,\"overDraftLimit\":-20.0}}"
              }
            else
              env
            end
        end)

        # Exhaust the staff `send_otp:` budget first ...
        staff_params = %{
          "user" => %{
            "phone" => unique_phone(),
            "registration" => "true",
            "token" => "some_token"
          }
        }

        staff_first = post(conn, Routes.api_v1_registration_path(conn, :send_otp, staff_params))
        assert json_response(staff_first, 200)

        staff_second = post(conn, Routes.api_v1_registration_path(conn, :send_otp, staff_params))
        assert json_response(staff_second, 429)

        # ... a web-channel request from the same IP is unaffected: it does not share the budget.
        web_channel_conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json_response(web_channel_conn, 200)

        # And the converse: exhaust the web-channel budget ...
        web_channel_second =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => @reachable_phone
            })
          )

        assert json_response(web_channel_second, 429)

        # ... a staff request from the same IP is unaffected in turn. Reset the staff bucket
        # first — it is still sitting at its own (count: 1) limit from staff_first/staff_second
        # above, which would otherwise return 429 for a reason that has nothing to do with the
        # web-channel budget we just exhausted, defeating the point of this assertion.
        ExRated.delete_bucket(staff_key)

        staff_params_2 = %{
          "user" => %{
            "phone" => unique_phone(),
            "registration" => "true",
            "token" => "some_token"
          }
        }

        staff_third =
          post(conn, Routes.api_v1_registration_path(conn, :send_otp, staff_params_2))

        assert json_response(staff_third, 200)
      end)
    end

    test "normalizes a loosely formatted phone number in the response body", %{conn: conn} do
      with_web_channel_enabled(fn ->
        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :request_otp, %{
              "phone" => "+91 98201 98765"
            })
          )

        assert json = json_response(conn, 200)
        assert get_in(json, ["data", "phone"]) == "919820198765"
      end)
    end
  end

  describe "verify_otp/2" do
    test "a correct code returns a valid contact-scoped token and resolves the contact", %{
      conn: conn,
      organization_id: organization_id
    } do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        code = OTP.generate_code(:web_channel, phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => code
            })
          )

        assert json = json_response(conn, 200)
        assert token = get_in(json, ["data", "token"])
        assert contact_id = get_in(json, ["data", "contact_id"])
        assert get_in(json, ["data", "phone"]) == phone

        assert {:ok, %{contact_id: ^contact_id, org_id: ^organization_id}} =
                 Token.verify_contact_token(token)

        assert {:ok, %Contact{phone: ^phone, organization_id: ^organization_id}} =
                 Repo.fetch_by(Contact, %{id: contact_id, organization_id: organization_id})
      end)
    end

    test "a wrong code returns 401 Invalid OTP", %{conn: conn} do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        OTP.generate_code(:web_channel, phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => "000000"
            })
          )

        assert json = json_response(conn, 401)
        assert get_in(json, ["error", "message"]) == "Invalid OTP"
      end)
    end

    test "cross-scope, direction 1: an :auth-scoped code is rejected by verify-otp", %{
      conn: conn
    } do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        # A code minted for the staff/registration `:auth` scope must never authenticate a
        # web-channel contact.
        auth_code = OTP.generate_code(:auth, phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => auth_code
            })
          )

        assert json = json_response(conn, 401)
        assert get_in(json, ["error", "message"]) == "Invalid OTP"
      end)
    end

    test "cross-scope, direction 2: a :web_channel-scoped code is rejected by the staff password reset endpoint",
         %{conn: conn} do
      # No flag needed: this direction never touches the web_channel controller — it only
      # proves a `:web_channel` code cannot authorize the staff `reset_password` (`:auth`-scoped)
      # endpoint. Modeled on `registration_controller_test.exs`'s "with an otp minted by the
      # trial signup flow" case, which asserts the same non-leakage for the `:trial` scope.
      user = Fixtures.user_fixture()
      web_channel_code = OTP.generate_code(:web_channel, user.phone)

      reset_params = %{
        "user" => %{
          "phone" => user.phone,
          "password" => "BrandNew1234!",
          "otp" => web_channel_code
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :reset_password, reset_params))

      assert json = json_response(conn, 500)
      assert json["error"]["status"] == 500
      assert json["error"]["message"] == "Couldn't update user password"
      assert Repo.get!(Users.User, user.id).password_hash == user.password_hash
    end

    test "replay: a code that verified once is rejected on a second attempt", %{conn: conn} do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        code = OTP.generate_code(:web_channel, phone)

        first =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => code
            })
          )

        assert json_response(first, 200)

        second =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => code
            })
          )

        assert json = json_response(second, 401)
        assert get_in(json, ["error", "message"]) == "Invalid OTP"
      end)
    end

    test "attempt lockout: a sixth wrong guess still returns the generic 401 Invalid OTP", %{
      conn: conn
    } do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        OTP.generate_code(:web_channel, phone)

        responses =
          for _ <- 1..6 do
            post(
              conn,
              Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
                "phone" => phone,
                "otp" => "000000"
              })
            )
          end

        last_response = List.last(responses)

        # `:attempt_blocked` (the 6th guess) must not leak a status or message different from
        # `:incorrect_code` (guesses 1-5) — both collapse to the same 401 Invalid OTP.
        assert json = json_response(last_response, 401)
        assert get_in(json, ["error", "message"]) == "Invalid OTP"
      end)
    end

    # Expiry (5 minute TTL) is intentionally not covered here: `PasswordlessAuth`'s code store is
    # a global process/ETS structure that is not injectable, so exercising real expiry would
    # require a literal 300-second sleep in the suite, which we were explicitly told not to add.
    # `OTP.verify_code/3` mapping a `{:error, :code_expired}` to this controller's generic 401 is
    # covered structurally instead: `verify_otp_for/4` collapses every `{:error, _}` reason
    # (`:incorrect_code`, `:code_expired`, `:does_not_exist`, `:attempt_blocked`) to the identical
    # response, and the wrong-code/attempt-lockout tests above already exercise that same
    # collapsing clause for the other three reasons.

    test "missing otp returns 422", %{conn: conn} do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{"phone" => phone})
          )

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "message"]) == "Phone number and OTP are required"
      end)
    end

    test "an invalid E.164 phone returns 422", %{conn: conn} do
      with_web_channel_enabled(fn ->
        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => "notaphone",
              "otp" => "123456"
            })
          )

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "message"])
      end)
    end

    test "an existing WhatsApp contact resolves to that contact, not a new one", %{conn: conn} do
      with_web_channel_enabled(fn ->
        existing_contact = Repo.get_by!(Contact, phone: @reachable_phone)
        code = OTP.generate_code(:web_channel, @reachable_phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => @reachable_phone,
              "otp" => code
            })
          )

        assert json = json_response(conn, 200)
        assert get_in(json, ["data", "contact_id"]) == existing_contact.id
      end)
    end

    test "prefers the flow-captured contact.fields.name over contact.name", %{
      conn: conn,
      organization_id: organization_id
    } do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        {:ok, _contact} =
          Contacts.create_contact(%{
            phone: phone,
            name: "WhatsApp Pushname",
            fields: %{
              "name" => %{"value" => "Priya", "label" => "Name", "type" => "string"}
            },
            organization_id: organization_id
          })

        code = OTP.generate_code(:web_channel, phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => code
            })
          )

        assert get_in(json_response(conn, 200), ["data", "name"]) == "Priya"
      end)
    end

    test "falls back to contact.name when contact.fields.name is absent", %{
      conn: conn,
      organization_id: organization_id
    } do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        {:ok, _contact} =
          Contacts.create_contact(%{
            phone: phone,
            name: "Ravi",
            organization_id: organization_id
          })

        code = OTP.generate_code(:web_channel, phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => code
            })
          )

        assert get_in(json_response(conn, 200), ["data", "name"]) == "Ravi"
      end)
    end

    test "returns a nil name when neither contact.fields.name nor contact.name is set", %{
      conn: conn
    } do
      phone = unique_phone()

      with_web_channel_enabled(fn ->
        code = OTP.generate_code(:web_channel, phone)

        conn =
          post(
            conn,
            Routes.api_v1_web_channel_auth_path(conn, :verify_otp, %{
              "phone" => phone,
              "otp" => code
            })
          )

        assert get_in(json_response(conn, 200), ["data", "name"]) == nil
      end)
    end
  end
end
