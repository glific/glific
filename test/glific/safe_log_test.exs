defmodule Glific.SafeLogTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Glific.SafeLog

  describe "safe_inspect/1" do
    test "passes plain strings through unchanged" do
      assert SafeLog.safe_inspect("hello") == inspect("hello")
    end

    test "passes non-Tesla terms through unchanged" do
      assert SafeLog.safe_inspect(42) == "42"
      assert SafeLog.safe_inspect(:ok) == ":ok"
      assert SafeLog.safe_inspect(%{a: 1}) == "%{a: 1}"
      assert SafeLog.safe_inspect({:error, "reason"}) == ~s({:error, "reason"})
    end

    test "strips __client__ from Tesla.Env so auth headers are not logged" do
      env = %Tesla.Env{
        status: 429,
        url: "https://api.example.com",
        __client__: %Tesla.Client{
          pre: [{Tesla.Middleware.Headers, :call, [[{"authorization", "Bearer secret-token"}]]}]
        }
      }

      result = SafeLog.safe_inspect(env)

      assert result =~ "429"
      assert result =~ "api.example.com"
      refute result =~ "Bearer"
      refute result =~ "secret-token"
      refute result =~ "authorization"
    end

    test "keeps all safe Tesla.Env fields intact after stripping client" do
      env = %Tesla.Env{
        status: 403,
        method: :get,
        url: "https://sheets.googleapis.com/v4/spreadsheets/abc123",
        body: ~s({"error": {"code": 403, "message": "Forbidden"}}),
        headers: [{"content-type", "application/json"}],
        __client__: %Tesla.Client{
          pre: [{Tesla.Middleware.Headers, :call, [[{"authorization", "Bearer ya29.secret"}]]}]
        }
      }

      result = SafeLog.safe_inspect(env)

      assert result =~ "403"
      assert result =~ "sheets.googleapis.com"
      assert result =~ "Forbidden"
      assert result =~ "content-type"
      refute result =~ "ya29.secret"
    end

    test "handles Tesla.Env with nil client safely" do
      env = %Tesla.Env{status: 200, __client__: nil}
      result = SafeLog.safe_inspect(env)

      assert result =~ "200"
      assert result =~ "__client__: nil"
    end
  end
end
