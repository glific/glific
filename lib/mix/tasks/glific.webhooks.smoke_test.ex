defmodule Mix.Tasks.Glific.Webhooks.SmokeTest do
  @shortdoc "Runs the flow-webhook smoke test against an org"

  @moduledoc """
  Calls each flow-webhook node's `call/2` with fixture input against a sandbox/staging org and
  prints a per-node `:ok | {:error, reason}` summary. Exits non-zero if any node errored, so it
  can gate a CI/staging check.

      mix glific.webhooks.smoke_test --org 1
      mix glific.webhooks.smoke_test --org 1 --assistant asst_123 --audio-url https://example.com/sample.ogg

  ## Options

    * `--org` (required) — organization id to probe
    * `--assistant` — assistant display id for the filesearch/voice nodes
    * `--audio-url` — reachable https audio URL for the STT/voice nodes
    * `--flow` / `--contact` — flow and contact ids used to sign the async callbacks

  The same probe runs on the live app from a Gigalixir `remote_console`:
  `Glific.Flows.Webhooks.Core.SmokeTest.run_all(org_id)`.
  """

  use Mix.Task

  alias Glific.Flows.Webhooks.Core.SmokeTest

  @switches [
    org: :integer,
    assistant: :string,
    audio_url: :string,
    flow: :integer,
    contact: :integer
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)

    org_id = opts[:org] || Mix.raise("--org <id> is required")

    org_id
    |> SmokeTest.run_all(overrides(opts))
    |> exit_status()
  end

  @spec overrides(keyword()) :: map()
  defp overrides(opts) do
    %{
      assistant_id: opts[:assistant],
      audio_url: opts[:audio_url],
      flow_id: opts[:flow],
      contact_id: opts[:contact]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec exit_status(%{String.t() => SmokeTest.outcome()}) :: :ok
  defp exit_status(results) do
    if Enum.any?(results, fn {_name, outcome} -> match?({:error, _reason}, outcome) end) do
      exit({:shutdown, 1})
    end

    :ok
  end
end
