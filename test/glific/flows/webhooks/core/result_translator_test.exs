defmodule Glific.Flows.Webhooks.Core.ResultTranslatorTest.StubAddress do
  defstruct [:city, :state]

  def to_flow_map(%__MODULE__{} = addr) do
    %{city: addr.city, state: addr.state, success: true}
  end
end

defmodule Glific.Flows.Webhooks.Core.ResultTranslatorTest.StubWebhook do
  use Glific.Flows.Webhooks.Sync, name: "stub_for_translator_test"
  @impl true
  def call(_fields, _ctx),
    do: {:ok, %Glific.Flows.Webhooks.Core.ResultTranslatorTest.StubAddress{city: "X", state: "Y"}}
end

defmodule Glific.Flows.Webhooks.Core.ResultTranslatorTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.Webhooks.{Geolocation, ResultTranslator}
  alias Glific.Flows.Webhooks.Geolocation.Address

  alias Glific.Flows.Webhooks.Core.ResultTranslatorTest.{StubAddress, StubWebhook}

  describe "to_legacy_structure/2 with Geolocation module" do
    test "{:ok, Address} returns success map with success: true" do
      address = %Address{
        city: "Bangalore",
        state: "Karnataka",
        country: "India",
        postal_code: "560001",
        district: "Bangalore Urban",
        address: "Bangalore, Karnataka, India"
      }

      result = ResultTranslator.to_legacy_structure({:ok, address}, Geolocation)

      assert is_map(result)
      assert result.success == true
      assert result.city == "Bangalore"
      assert result.state == "Karnataka"
      assert result.country == "India"
    end

    test "{:error, message} returns the error string directly" do
      result = ResultTranslator.to_legacy_structure({:error, "No address found"}, Geolocation)

      assert result == "No address found"
    end

    test "{:error, message} is a plain string (not a map)" do
      result = ResultTranslator.to_legacy_structure({:error, "some error"}, Geolocation)

      refute is_map(result)
      assert is_binary(result)
    end
  end

  describe "to_legacy_structure/2 passthrough behaviour" do
    test "existing success map passes through unchanged" do
      map = %{success: true, city: "Delhi"}
      assert ResultTranslator.to_legacy_structure(map, Geolocation) == map
    end

    test "existing failure map passes through unchanged" do
      map = %{success: false, reason: "API error"}
      assert ResultTranslator.to_legacy_structure(map, Geolocation) == map
    end

    test "plain binary string passes through unchanged" do
      str = "some legacy string result"
      assert ResultTranslator.to_legacy_structure(str, Geolocation) == str
    end

    test "nil passes through unchanged" do
      assert ResultTranslator.to_legacy_structure(nil, Geolocation) == nil
    end
  end

  describe "to_legacy_structure/2 with stub webhook module" do
    test "stub module encoder produces success map from struct" do
      stub_addr = %StubAddress{city: "Mumbai", state: "Maharashtra"}
      result = ResultTranslator.to_legacy_structure({:ok, stub_addr}, StubWebhook)

      assert result.success == true
      assert result.city == "Mumbai"
    end

    test "{:error, ...} with unknown module still returns the string" do
      result = ResultTranslator.to_legacy_structure({:error, "oops"}, StubWebhook)
      assert result == "oops"
    end
  end

  describe "to_legacy_structure/2 with unknown module (no custom encoder)" do
    test "unknown module with plain map {:ok, map} returns map with success: true" do
      result = ResultTranslator.to_legacy_structure({:ok, %{foo: "bar"}}, __MODULE__)

      assert is_map(result)
      assert result.success == true
    end

    test "unknown module with scalar {:ok, value} returns map with success: true" do
      result = ResultTranslator.to_legacy_structure({:ok, "some value"}, __MODULE__)

      assert is_map(result)
      assert result.success == true
    end
  end
end
