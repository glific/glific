defmodule Glific.Providers.InstrumentationTest.StubAdapter do
  @moduledoc false
  # A bare adapter with no overrides, to exercise the generic mixin defaults.
  use Glific.Providers.Instrumentation, provider: "stub"
end

defmodule Glific.Providers.InstrumentationTest do
  use Glific.DataCase

  alias Glific.{Fixtures, Providers.Instrumentation}
  alias Glific.Providers.InstrumentationTest.StubAdapter

  describe "adapter mixin defaults" do
    test "supplies the provider tag and an identity classify_send/2" do
      assert StubAdapter.provider() == "stub"
      assert StubAdapter.classify_send(:error, %{error_code: 472}) == :error
      assert StubAdapter.classify_send(:success, %{}) == :success
    end

    test "injects track_* helpers that delegate to the core and return :ok",
         %{organization_id: organization_id} do
      assert :ok =
               StubAdapter.track_send(:success, is_hsm: true, organization_id: organization_id)

      assert :ok = StubAdapter.track_send(:error, organization_id: organization_id)
      assert :ok = StubAdapter.track_send(:timeout)
      assert :ok = StubAdapter.track_receive("text handler", organization_id)
      assert :ok = StubAdapter.track_status(:delivered, organization_id)
      assert :ok = StubAdapter.track_action("some_action", :success, organization_id)
      assert :ok = StubAdapter.track_action("some_action", :failure, organization_id)
    end
  end

  describe "check_inbound_staleness/0" do
    test "returns :ok and flags when the whole platform has no recent inbound message" do
      # A fresh DataCase seeds no messages, so the cross-org lookback finds
      # nothing and the stale branch fires.
      assert :ok = Instrumentation.check_inbound_staleness()
    end

    test "returns :ok when any organization has a recent inbound message",
         %{organization_id: organization_id} do
      Fixtures.message_fixture(%{flow: :inbound, organization_id: organization_id})
      assert :ok = Instrumentation.check_inbound_staleness()
    end
  end
end
