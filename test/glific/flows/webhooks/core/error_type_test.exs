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

    test "maps upstream blips to :transient" do
      assert ErrorType.class(:rate_limited) == :transient
      assert ErrorType.class(:service_unavailable) == :transient
    end

    test "returns nil for an unrecognised atom (caller fails safe to system)" do
      assert ErrorType.class(:not_a_real_error_type) == nil
      assert ErrorType.class(nil) == nil
    end
  end
end
