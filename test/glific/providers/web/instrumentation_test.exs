defmodule Glific.Providers.Web.InstrumentationTest do
  use Glific.DataCase

  alias Glific.Providers.Web.Instrumentation

  test "tags metrics with the web provider" do
    assert Instrumentation.provider() == "web"
  end

  test "a token event outside the fixed set is refused, so counter names stay bounded" do
    assert :ok = Instrumentation.track_token("renewed", 1)
    assert_raise FunctionClauseError, fn -> Instrumentation.track_token("something_else", 1) end
  end

  test "passes every send status through unchanged" do
    assert Instrumentation.classify_send(:success, %{}) == :success
    assert Instrumentation.classify_send(:error, %{}) == :error
  end
end
