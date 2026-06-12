defmodule Glific.Flows.Webhook.HeaderRedactor do
  @moduledoc """
  Redacts credential-bearing values from webhook request headers before they
  are persisted to `webhook_logs`.

  Webhook headers are attacker-irrelevant but operator-sensitive: they carry
  the `X-API-KEY` Glific injects for Kaapi calls, and — for user-authored
  GET/POST webhook nodes — whatever the NGO pastes in (Google `AIza…` keys,
  `Authorization: Bearer …`, Stripe `sk_live_…`, etc.). Persisting them raw
  leaks those secrets into the webhook log UI and any downstream sync.

  We cannot allow-list header *names*, because a flow author can name a header
  anything. So redaction is driven by two independent signals, applied centrally
  in `Glific.Flows.Webhook.create_log/4` so every webhook path is covered:

    1. **Key name** — the header name matches a well-known credential name
       (`authorization`, `x-api-key`, `*-token`, `secret`, `cookie`, …).
       This is deterministic for the keys we control (e.g. the injected
       `X-API-KEY`).
    2. **Value shape** — the value *looks* like a credential (scheme-prefixed
       `Bearer …`, a JWT, a vendor-prefixed key like `sk-`/`xoxb-`/`AIza`,
       a long high-entropy token, a 32+ char hex digest, or a UUID).
       This catches arbitrary user-supplied secrets we can't name in advance.

  A header is redacted if *either* signal fires. The real headers used for the
  outbound HTTP call are never touched — only the copy written to the log.
  """

  @redacted "[REDACTED]"

  # Header names that always carry credentials, regardless of value.
  @sensitive_key_patterns [
    ~r/authorization/i,
    ~r/auth[-_]?token/i,
    ~r/\bauth\b/i,
    ~r/api[-_ ]?key/i,
    ~r/access[-_ ]?token/i,
    ~r/\btoken\b/i,
    ~r/secret/i,
    ~r/credential/i,
    ~r/private[-_ ]?key/i,
    ~r/password|passwd|pwd/i,
    ~r/signature/i,
    ~r/bearer/i,
    ~r/cookie/i
  ]

  # Value shapes that indicate a credential.
  @credential_value_patterns [
    ~r/^(bearer|basic|token|apikey|digest)\s+\S+/i,
    ~r/^[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}$/,
    # AKIA…, ya29… (Stripe, Slack, OpenAI, Google, GitHub, GitLab, AWS, OAuth)
    ~r/^(sk|pk|rk|xox[a-z]|whsec|aiza|gh[opusr]|github_pat|glpat|akia|asia|ya29|shpat|shpss)[-_]?[A-Za-z0-9\-_]{10,}/i,
    ~r/^[a-fA-F0-9]{32,}$/,
    ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
  ]

  # A long, unbroken token of credential-ish characters. Gated on containing
  # BOTH a letter and a digit so alpha-only values (MIME types, encodings like
  # "application/json") and pure-numeric ids don't get falsely redacted.
  @high_entropy_pattern ~r|^[A-Za-z0-9\-_/+.=:~]{20,}$|

  @doc """
  Redact credential-bearing values from a webhook headers map.

  Returns the map with sensitive values replaced by `"[REDACTED]"`. Header
  names are preserved (so logs stay debuggable). Non-map input is returned
  unchanged.
  """
  @spec redact(map() | nil | any()) :: map() | nil | any()
  def redact(headers) when is_map(headers), do: Map.new(headers, &redact_entry/1)
  def redact(headers), do: headers

  @spec redact_entry({any(), any()}) :: {any(), any()}
  defp redact_entry({key, value}) do
    if sensitive_key?(key) or credential_value?(value) do
      {key, @redacted}
    else
      {key, value}
    end
  end

  @spec sensitive_key?(any()) :: boolean()
  defp sensitive_key?(key) do
    key_string = to_string(key)
    Enum.any?(@sensitive_key_patterns, &Regex.match?(&1, key_string))
  end

  @spec credential_value?(any()) :: boolean()
  defp credential_value?(value) when is_binary(value) do
    trimmed = String.trim(value)

    Enum.any?(@credential_value_patterns, &Regex.match?(&1, trimmed)) or
      high_entropy_token?(trimmed)
  end

  defp credential_value?(_value), do: false

  @spec high_entropy_token?(String.t()) :: boolean()
  defp high_entropy_token?(value) do
    Regex.match?(@high_entropy_pattern, value) and
      String.match?(value, ~r/[A-Za-z]/) and
      String.match?(value, ~r/[0-9]/)
  end
end
