defmodule Glific.Providers.Gupshup.InstrumentationTest do
  use Glific.DataCase

  alias Glific.Providers.Gupshup.Instrumentation

  describe "provider/0" do
    test "tags metrics with the gupshup provider" do
      assert Instrumentation.provider() == "gupshup"
    end
  end

  describe "classify_send/2" do
    test "reclassifies a frequency-capped error to :frequency_capped" do
      assert Instrumentation.classify_send(:error, %{error_code: 131_049}) == :frequency_capped
      assert Instrumentation.classify_send(:error, %{error_code: "131049"}) == :frequency_capped
    end

    test "keeps other errors as :error" do
      assert Instrumentation.classify_send(:error, %{error_code: 471}) == :error
      assert Instrumentation.classify_send(:error, %{}) == :error
    end

    test "passes non-error statuses through unchanged" do
      assert Instrumentation.classify_send(:success, %{}) == :success
      assert Instrumentation.classify_send(:timeout, %{error_code: 131_049}) == :timeout
    end
  end

  describe "classify_status/2" do
    test "reclassifies a frequency-capped failed callback to :frequency_capped" do
      assert Instrumentation.classify_status(:error, %{error_code: 131_049}) == :frequency_capped
      assert Instrumentation.classify_status(:error, %{error_code: "131049"}) == :frequency_capped
    end

    test "keeps other failed callbacks as :error" do
      assert Instrumentation.classify_status(:error, %{error_code: 471}) == :error
      assert Instrumentation.classify_status(:error, %{error_code: nil}) == :error
      assert Instrumentation.classify_status(:error, %{}) == :error
    end

    test "passes non-error statuses through even if a cap code is present" do
      assert Instrumentation.classify_status(:delivered, %{}) == :delivered
      assert Instrumentation.classify_status(:read, %{error_code: 131_049}) == :read
    end
  end

  describe "frequency_capped?/1" do
    test "is true only for the configured cap code, as integer or string" do
      assert Instrumentation.frequency_capped?(131_049)
      assert Instrumentation.frequency_capped?("131049")
    end

    test "is false for other codes, nil and non-numeric input" do
      refute Instrumentation.frequency_capped?(471)
      refute Instrumentation.frequency_capped?(nil)
      refute Instrumentation.frequency_capped?("not-a-code")
    end
  end

  describe "inherited track helpers" do
    test "delegate to the core as the gupshup provider and return :ok",
         %{organization_id: organization_id} do
      assert :ok =
               Instrumentation.track_send(:error,
                 organization_id: organization_id,
                 error_code: 131_049
               )

      assert :ok = Instrumentation.track_receive("text handler", organization_id)
      assert :ok = Instrumentation.track_status(:read, organization_id)
      assert :ok = Instrumentation.track_status(:error, organization_id, error_code: 131_049)
      assert :ok = Instrumentation.track_action("hsm_sync", :success, organization_id)
    end
  end
end
