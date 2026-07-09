defmodule Glific.Flows.Webhooks.Core.ErrorTypeTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.ErrorType

  describe "class/1" do
    test "maps Glific-owned provisioning gaps to :system" do
      assert ErrorType.class(:kaapi_not_active) == :system
      assert ErrorType.class(:missing_api_key) == :system
      assert ErrorType.class(:tts_upload_failed) == :system
    end

    test "maps NGO / flow-author mistakes to :config" do
      assert ErrorType.class(:invalid_json_body) == :config
      assert ErrorType.class(:unknown_webhook_fn) == :config
      assert ErrorType.class(:invalid_media_url) == :config
      assert ErrorType.class(:assistant_not_found) == :config
      assert ErrorType.class(:invalid_geocoding) == :config
      assert ErrorType.class(:empty_input) == :config
      assert ErrorType.class(:flow_category_unmatched) == :config
    end

    test "maps upstream blips to :transient" do
      assert ErrorType.class(:rate_limited) == :transient
      assert ErrorType.class(:service_unavailable) == :transient
    end

    test "maps a benign late/duplicate callback to :stale" do
      assert ErrorType.class(:stale_callback) == :stale
    end

    test "returns nil for an unknown atom so the caller defers to the engine" do
      assert ErrorType.class(:not_a_real_error_type) == nil
      assert ErrorType.class(nil) == nil
    end
  end
end
