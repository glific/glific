defmodule Glific.Flows.Webhooks.ResultTranslatorTest.UnknownWebhook do
  @moduledoc false
  def name, do: "unknown"
end

defmodule Glific.Flows.Webhooks.ResultTranslatorTest.MyStruct do
  @moduledoc false
  defstruct [:value]
end

defmodule Glific.Flows.Webhooks.ResultTranslatorTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.{Geolocation, ResultTranslator}
  alias Glific.Flows.Webhooks.Geolocation.Address
  alias Glific.Flows.Webhooks.ResultTranslatorTest.UnknownWebhook

  describe "to_legacy_structure/2" do
    test "encodes {:ok, struct} to a legacy success map" do
      address = %Address{
        city: "San Francisco",
        state: "CA",
        country: "USA",
        postal_code: "94102",
        district: "N/A",
        address: "San Francisco, CA, USA"
      }

      result = ResultTranslator.to_legacy_structure({:ok, address}, Geolocation)

      assert result[:success] == true
      assert result[:city] == "San Francisco"
      assert result[:state] == "CA"
    end

    test "encodes {:error, message} to a bare string for the Failure flow route" do
      assert ResultTranslator.to_legacy_structure({:error, "geocoding failed"}, Geolocation) ==
               "geocoding failed"
    end

    test "default encoder adds success: true for plain maps on unknown modules" do
      assert ResultTranslator.to_legacy_structure({:ok, %{foo: "bar"}}, UnknownWebhook) == %{
               foo: "bar",
               success: true
             }
    end

    test "passes legacy map responses through unchanged" do
      legacy = %{success: false, error: "still a map"}
      assert ResultTranslator.to_legacy_structure(legacy, Geolocation) == legacy
    end

    test "default encoder adds success: true for structs on unknown modules" do
      alias Glific.Flows.Webhooks.ResultTranslatorTest.MyStruct

      result =
        ResultTranslator.to_legacy_structure({:ok, %MyStruct{value: 42}}, UnknownWebhook)

      assert result[:success] == true
      assert result[:value] == 42
    end

    test "default encoder wraps scalar values in a success map" do
      assert ResultTranslator.to_legacy_structure({:ok, "hello"}, UnknownWebhook) == %{
               success: true,
               value: "hello"
             }
    end
  end
end
