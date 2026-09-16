defmodule Glific.Flows.Webhook.HeaderRedactorTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhook.HeaderRedactor

  @redacted "[REDACTED]"

  describe "redact/1 — non-map input" do
    test "passes through nil and non-map values unchanged" do
      assert HeaderRedactor.redact(nil) == nil
      assert HeaderRedactor.redact("not a map") == "not a map"
      assert HeaderRedactor.redact([{"a", "b"}]) == [{"a", "b"}]
    end

    test "returns an empty map unchanged" do
      assert HeaderRedactor.redact(%{}) == %{}
    end
  end

  describe "redact/1 — sensitive key names (redacted regardless of value)" do
    for key <- [
          "Authorization",
          "authorization",
          "X-API-KEY",
          "x-api-key",
          "api_key",
          "Access-Token",
          "X-Auth-Token",
          "X-Secret",
          "Cookie",
          "Set-Cookie",
          "Private-Key",
          "Password",
          "X-Glific-Signature"
        ] do
      test "redacts header named #{key} even with a benign value" do
        assert %{unquote(key) => @redacted} ==
                 HeaderRedactor.redact(%{unquote(key) => "anything"})
      end
    end

    test "redacts atom-keyed sensitive headers" do
      assert %{authorization: @redacted} ==
               HeaderRedactor.redact(%{authorization: "x"})
    end
  end

  describe "redact/1 — credential-shaped values (arbitrary key name)" do
    credentials = [
      {"bearer", "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"},
      {"basic", "Basic dXNlcjpwYXNzd29yZA=="},
      {"jwt", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.SflKxwRJSMeKKF2QT4fwpMeJf36"},
      # Obviously-fake placeholders: still match the redactor's vendor-prefix
      # regex, but use hyphens / low entropy so GitHub push-protection's
      # provider-specific secret detectors don't flag them as real keys.
      {"google", "AIza-FAKE-GOOGLE-API-KEY-PLACEHOLDER"},
      {"stripe", "sk-FAKE-STRIPE-KEY-PLACEHOLDER"},
      {"slack", "xoxb-FAKE-SLACK-TOKEN-PLACEHOLDER"},
      {"github", "ghp-FAKE-GITHUB-TOKEN-PLACEHOLDER"},
      {"aws", "AKIA-FAKE-AWS-KEY-PLACEHOLDER"},
      {"hex_digest", "a3f1c2e4b5d6a7f8e9b0c1d2e3f4a5b6"},
      {"uuid", "550e8400-e29b-41d4-a716-446655440000"},
      {"long_token", "Xy7Kp2Qr9Tn4Vb6Wm1Zc8Ld3Hf5Gj0"}
    ]

    for {name, value} <- credentials do
      test "redacts #{name}-style value under an innocuous header name" do
        assert %{"X-Custom" => @redacted} ==
                 HeaderRedactor.redact(%{"X-Custom" => unquote(value)})
      end
    end
  end

  describe "redact/1 — benign values are preserved" do
    for value <- [
          "application/json",
          "application/x-www-form-urlencoded",
          "text/html; charset=utf-8",
          "gzip, deflate, br",
          "en-US,en;q=0.9",
          "keep-alive",
          "no-cache",
          "utf-8",
          "12345",
          "Mozilla/5.0 (Macintosh)",
          "max-age=3600"
        ] do
      test "keeps benign value #{inspect(value)}" do
        assert %{"X-Custom" => unquote(value)} ==
                 HeaderRedactor.redact(%{"X-Custom" => unquote(value)})
      end
    end

    test "leaves non-binary values untouched" do
      assert %{"X-Count" => 42, "X-Flag" => true} ==
               HeaderRedactor.redact(%{"X-Count" => 42, "X-Flag" => true})
    end
  end

  describe "redact/1 — mixed map" do
    test "redacts only the sensitive entries and keeps the rest" do
      headers = %{
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "X-API-KEY" => "kp_live_secret_value_123",
        "Authorization" => "Bearer abc.def.ghi",
        "X-Trace-Id" => "trace-001"
      }

      assert %{
               "Accept" => "application/json",
               "Content-Type" => "application/json",
               "X-API-KEY" => @redacted,
               "Authorization" => @redacted,
               "X-Trace-Id" => "trace-001"
             } == HeaderRedactor.redact(headers)
    end
  end
end
