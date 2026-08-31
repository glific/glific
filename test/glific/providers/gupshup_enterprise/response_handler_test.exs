defmodule Glific.Providers.Gupshup.Enterprise.ResponseHandlerTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Messages.Message,
    Providers.Gupshup.Enterprise.ResponseHandler,
    Repo
  }

  # Mirror the worker: the send-time message is the Oban-serialised minimal map
  # (string keys), built from a persisted message so the success/error handlers
  # have a row to update.
  defp send_message(attrs \\ %{}) do
    Fixtures.message_fixture(Map.merge(%{flow: :outbound}, attrs))
    |> Message.to_minimal_map()
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp reload(message), do: Repo.get!(Message, message["id"])

  describe "handle_response/2 — Tesla responses" do
    test "4xx marks the message errored and is not retried (returns :ok)" do
      message = send_message()

      body =
        Jason.encode!(%{"response" => %{"details" => "invalid destination address"}})

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 400, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :error
      assert reloaded.errors["payload"]["payload"]["reason"] == "invalid destination address"
    end

    test "5xx (catch-all) returns an error tuple built from the error payload" do
      message = send_message()

      body =
        Jason.encode!(%{"response" => %{"details" => "internal server error"}})

      assert {:error, %{"payload" => %{"payload" => %{"reason" => "internal server error"}}}} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 500, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
    end

    # Regression for AppSignal incident #363 (sibling bug found via blast-radius
    # grep on the Maytapi fix): Gupshup Enterprise (or an intermediary like
    # Cloudflare) can return a non-JSON plaintext body on infra-level failures,
    # which used to crash the Oban send job with a Jason.DecodeError.
    test "4xx with a non-JSON (plaintext) body does not crash and still errors the message" do
      message = send_message()
      body = "error code: 522\n"

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 400, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :error

      assert reloaded.errors["payload"]["payload"]["reason"] =~ "error code: 522"
    end

    test "non-2xx/4xx (catch-all) with a non-JSON (plaintext) body does not crash" do
      message = send_message()
      body = "error code: 522\n"

      assert {:error, %{"payload" => %{"payload" => %{"reason" => reason}}}} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 522, body: body}},
                 message
               )

      assert reason =~ "error code: 522"
      assert reload(message).bsp_status == :error
    end

    # Regression for AppSignal incident #363 (round 2): Gupshup Enterprise can
    # also send a non-JSON plaintext 2xx body, which used to crash
    # check_message_status/1 with a Jason.DecodeError before add_success_payload
    # or add_error_payload were ever reached. It now treats the body as an
    # error and routes through the (already-guarded) error path.
    test "2xx with a non-JSON (plaintext) body does not crash and is routed to the error path" do
      message = send_message()
      body = "error code: 522\n"

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 200, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :error
      assert reloaded.errors["payload"]["payload"]["reason"] =~ "error code: 522"
    end
  end
end
