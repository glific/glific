defmodule Glific.Providers.Web.InstrumentationTest do
  use Glific.DataCase

  alias Glific.Providers.Web.Instrumentation

  test "tags metrics with the web provider" do
    assert Instrumentation.provider() == "web"
  end

  test "passes every send status through unchanged" do
    assert Instrumentation.classify_send(:success, %{}) == :success
    assert Instrumentation.classify_send(:error, %{}) == :error
  end
end
