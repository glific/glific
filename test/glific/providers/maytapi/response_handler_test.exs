defmodule Glific.Providers.Maytapi.ResponseHandlerTest do
  use ExUnit.Case, async: true

  alias Glific.Providers.Maytapi.ResponseHandler

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
end
