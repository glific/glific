defmodule Glific.Providers.Maytapi.ResponseHandlerTest do
  # DataCase rather than a bare ExUnit.Case: the `handle_response/2` tests below
  # persist and reload a WAMessage. `phone_level_error?/1` stays pure.
  use Glific.DataCase

  alias Glific.{
    Fixtures,
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
