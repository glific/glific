defmodule Glific.Flows.Webhooks.Core.ErrorTypeTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.ErrorType

  describe "class/1" do
    test "maps Glific-owned provisioning gaps / unjudgeable failures to :system" do
      assert ErrorType.class(:missing_api_key) == :system
      assert ErrorType.class(:unknown) == :system
    end

    test "maps NGO / flow-author mistakes to :config" do
      assert ErrorType.class(:invalid_media_url) == :config
      assert ErrorType.class(:invalid_geocoding) == :config
      assert ErrorType.class(:empty_input) == :config
      assert ErrorType.class(:invalid_input) == :config
    end

    test "maps upstream blips to :system (no retry, so a blip is a real failure worth paging on)" do
      assert ErrorType.class(:rate_limited) == :system
      assert ErrorType.class(:service_unavailable) == :system
    end

    test "returns nil for an unrecognised atom (caller fails safe to system)" do
      assert ErrorType.class(:not_a_real_error_type) == nil
      assert ErrorType.class(nil) == nil
    end
  end

  describe "from_http_status/1" do
    test "a 429 is a rate-limit blip → :rate_limited (system)" do
      assert ErrorType.from_http_status(429) == :rate_limited
      assert ErrorType.class(:rate_limited) == :system
    end

    test "a 408 request timeout is a transient upstream stall → :service_unavailable (system)" do
      assert ErrorType.from_http_status(408) == :service_unavailable
      assert ErrorType.class(:service_unavailable) == :system
    end

    test "any other 4xx is a rejected request → :invalid_input (config)" do
      assert ErrorType.from_http_status(400) == :invalid_input
      assert ErrorType.from_http_status(404) == :invalid_input
      assert ErrorType.from_http_status(422) == :invalid_input
      assert ErrorType.class(:invalid_input) == :config
    end

    test "a 5xx is an upstream outage → :unknown (system)" do
      assert ErrorType.from_http_status(500) == :unknown
      assert ErrorType.from_http_status(503) == :unknown
      assert ErrorType.class(:unknown) == :system
    end

    test "a non-integer status (transport atom, raw body, nil) fails safe to :unknown" do
      assert ErrorType.from_http_status(:timeout) == :unknown
      assert ErrorType.from_http_status("File download failed") == :unknown
      assert ErrorType.from_http_status(%{"error" => "boom"}) == :unknown
      assert ErrorType.from_http_status(nil) == :unknown
    end
  end
end
