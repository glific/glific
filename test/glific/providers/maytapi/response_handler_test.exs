defmodule Glific.Providers.Maytapi.ResponseHandlerTest do
  # DataCase rather than a bare ExUnit.Case: the `handle_response/2` tests below
  # persist and reload a WAMessage. `phone_level_error?/1` stays pure.
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Fixtures,
    Notifications.Notification,
    Providers.Maytapi.ResponseHandler,
    Repo,
    WAGroup.WAMessage
  }

  # Mirror the worker: the send-time message is the Oban-serialised minimal map
  # (string keys), built from a persisted message so the success/error handlers
  # have a row to update.
  defp send_message(attrs) do
    attrs
    |> Map.put(:flow, :outbound)
    |> Fixtures.wa_message_fixture()
    |> WAMessage.to_minimal_map()
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp reload(message), do: Repo.get!(WAMessage, message["id"])

  defp critical_notification_exists?(ctx, substring) do
    Notification
    |> where([n], n.organization_id == ^ctx.organization_id)
    |> Repo.all()
    |> Enum.any?(fn n -> n.severity == "Critical" and String.contains?(n.message, substring) end)
  end

  describe "phone_level_error?/1" do
    test "returns true for any 5xx response" do
      assert ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 500, body: ""}})
      assert ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 502, body: ""}})
      assert ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 599, body: ""}})
    end

    test "returns true for a 4xx whose message mentions phone/device/instance/session" do
      for word <- ~w(phone device instance session) do
        body = Jason.encode!(%{"message" => "The #{word} is disconnected"})

        assert ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 400, body: body}}),
               "expected #{word} to be classified as a phone-level error"
      end
    end

    test "matching is case-insensitive" do
      body = Jason.encode!(%{"message" => "PHONE not active"})
      assert ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 401, body: body}})
    end

    test "returns false for a 4xx whose message looks like a client problem" do
      body = Jason.encode!(%{"message" => "You dont own this number"})
      refute ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 400, body: body}})
    end

    test "returns false for a 4xx whose JSON body has no message key" do
      body = Jason.encode!(%{"success" => false})
      refute ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 422, body: body}})
    end

    test "returns false for a 4xx whose message is not a binary" do
      body = Jason.encode!(%{"message" => 123})
      refute ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 400, body: body}})
    end

    test "returns false for a 4xx with a malformed (non-JSON) body" do
      refute ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 400, body: "not json"}})
    end

    test "returns false for a successful 2xx response" do
      refute ResponseHandler.phone_level_error?({:ok, %Tesla.Env{status: 200, body: "{}"}})
    end

    test "returns false for a transport-level error tuple" do
      refute ResponseHandler.phone_level_error?({:error, :timeout})
    end

    test "returns false for anything else" do
      refute ResponseHandler.phone_level_error?(:unexpected)
      refute ResponseHandler.phone_level_error?(nil)
    end
  end

  describe "handle_response/2 — Tesla responses" do
    test "2xx marks the message enqueued (success send)", attrs do
      message = send_message(attrs)
      body = Jason.encode!(%{"data" => %{"msgId" => "maytapi-success-id"}})

      assert {:ok, _message} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 200, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :enqueued
      assert reloaded.bsp_id == "maytapi-success-id"
    end

    test "4xx marks the message errored and is not retried (returns :ok)", attrs do
      message = send_message(attrs)
      body = Jason.encode!(%{"success" => false, "message" => "You dont own this number"})

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 400, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
    end

    test "5xx returns an error tuple so the caller can retry", attrs do
      message = send_message(attrs)
      body = Jason.encode!(%{"success" => false, "message" => "phone is disconnected"})

      assert {:error, _body} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 500, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
    end

    # Regression for AppSignal incident #363: Maytapi (or an intermediary like
    # Cloudflare) can return a non-JSON plaintext body on infra-level failures,
    # which used to crash the WAWorker Oban job with a Jason.DecodeError.
    test "4xx with a non-JSON (plaintext) body does not crash and still notifies", attrs do
      message = send_message(attrs)
      body = "error code: 522\n"

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 400, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
      assert critical_notification_exists?(attrs, "error code: 522")
    end

    test "non-2xx/4xx (catch-all) with a non-JSON (plaintext) body does not crash and still notifies",
         attrs do
      message = send_message(attrs)
      body = "error code: 522\n"

      assert {:error, ^body} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 522, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
      assert critical_notification_exists?(attrs, "error code: 522")
    end

    # Regression for AppSignal incident #363 (round 2): Maytapi can also send
    # a non-JSON plaintext 2xx body (e.g. after an infra-level hiccup), which
    # used to crash handle_success_response/2 with a Jason.DecodeError. It now
    # falls back to the same error path as a real error response.
    test "2xx with a non-JSON (plaintext) body does not crash and falls back to the error path",
         attrs do
      message = send_message(attrs)
      body = "error code: 522\n"

      assert {:error, ^body} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 200, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
      assert critical_notification_exists?(attrs, "error code: 522")
    end
  end

  describe "handle_response/2 — transport errors" do
    test "a timeout falls back to the default error body", attrs do
      message = send_message(attrs)

      assert {:error, _body} = ResponseHandler.handle_response({:error, :timeout}, message)
      assert reload(message).bsp_status == :error
    end

    test "a non-timeout transport error is also handled", attrs do
      message = send_message(attrs)

      assert {:error, _body} = ResponseHandler.handle_response({:error, :econnrefused}, message)
      assert reload(message).bsp_status == :error
    end
  end
end
