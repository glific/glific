defmodule Glific.Providers.Maytapi.InstrumentationTest do
  use Glific.DataCase

  alias Glific.Providers.Maytapi.Instrumentation

  describe "provider/0" do
    test "tags metrics with the maytapi provider" do
      assert Instrumentation.provider() == "maytapi"
    end
  end

  describe "classify_send/2" do
    test "passes every status through unchanged (no custom classification)" do
      assert Instrumentation.classify_send(:success, %{}) == :success
      assert Instrumentation.classify_send(:error, %{}) == :error
      assert Instrumentation.classify_send(:timeout, %{}) == :timeout
    end

    test "does not reclassify Gupshup's frequency-cap code" do
      assert Instrumentation.classify_send(:error, %{error_code: 472}) == :error
    end
  end

  describe "inherited track helpers" do
    test "delegate to the core as the maytapi provider and return :ok",
         %{organization_id: organization_id} do
      assert :ok = Instrumentation.track_send(:success, organization_id: organization_id)
      assert :ok = Instrumentation.track_send(:error, organization_id: organization_id)
      assert :ok = Instrumentation.track_send(:timeout)
      assert :ok = Instrumentation.track_receive("text handler", organization_id)
      assert :ok = Instrumentation.track_status(:seen, organization_id)
      assert :ok = Instrumentation.track_status(:unknown, organization_id)
      assert :ok = Instrumentation.track_action("group_sync", :success, organization_id)
    end
  end
end
