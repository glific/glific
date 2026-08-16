defmodule Glific.Scripts.SignatureAudit do
  @moduledoc """
  Read-only audit of webhook signature usage, to size the blast radius before rotating
  `signature_phrase` for existing organizations.

  Reports four things over the last `days` of `webhook_logs`:

    1. outbound webhook calls by method — each one carries an `X-Glific-Signature` header
    2. dispatches to the async Kaapi nodes, which expect a signed `/webhook/flow_resume` callback
    3. how many organizations still hold a shipped default phrase, a blank one, or their own
    4. the intersection of "changed the phrase" and "makes http calls" — the rotation risk list

  `signature_phrase` is Cloak-encrypted, so it cannot be filtered in SQL; the phrase buckets are
  computed in memory after loading every organization.

  ## Run from IEx (`gigalixir ps:remote_console`)

      iex> Glific.Scripts.SignatureAudit.run()
      :ok

      # widen the window
      iex> Glific.Scripts.SignatureAudit.run(90)
  """

  import Ecto.Query

  alias Glific.{
    Flows.WebhookLog,
    Partners.Organization,
    Repo
  }

  @known_defaults ["Please change me, NOW!", "This is a dummy secret"]
  @async_nodes ["speech_to_text", "text_to_speech", "filesearch-gpt", "voice-filesearch-gpt"]

  @doc """
  Prints the audit for the last `days` days (default 30).
  """
  @spec run(pos_integer()) :: :ok
  def run(days \\ 30) do
    http_org_ids = http_org_ids(days)
    organizations = Repo.all(Organization, skip_organization_id: true)
    phrase_groups = group_by_phrase(organizations)
    changed = Map.get(phrase_groups, :changed, [])

    IO.puts("\n=== signature audit, last #{days} days ===\n")

    IO.puts("1. outbound webhook calls by method (each carries X-Glific-Signature)")

    Enum.each(calls_by_method(days), fn {method, count} ->
      IO.puts("     #{method}: #{count}")
    end)

    IO.puts("     orgs making http calls: #{MapSet.size(http_org_ids)}")

    resume = resume_dispatches_by_org(days)
    IO.puts("\n2. flow_resume callbacks expected (async Kaapi dispatches)")
    IO.puts("     orgs using it: #{length(resume)}")
    IO.puts("     total dispatches: #{resume |> Enum.map(&elem(&1, 1)) |> Enum.sum()}")
    Enum.each(resume, fn {org_id, count} -> IO.puts("     org #{org_id}: #{count}") end)

    IO.puts("\n3. signature phrase state (#{length(organizations)} orgs)")

    Enum.each([:changed, :still_default, :blank], fn group ->
      IO.puts("     #{group}: #{length(Map.get(phrase_groups, group, []))}")
    end)

    IO.puts("\n4. changed the phrase AND makes http calls — rotation risk list")
    changed_and_http = Enum.filter(changed, &MapSet.member?(http_org_ids, &1.id))
    IO.puts("     count: #{length(changed_and_http)}")

    Enum.each(changed_and_http, fn org ->
      IO.puts("     org #{org.id} (#{org.shortcode}) #{org.email}")
    end)

    IO.puts("")
    :ok
  end

  @spec calls_by_method(pos_integer()) :: [{String.t(), non_neg_integer()}]
  defp calls_by_method(days) do
    WebhookLog
    |> where([w], w.inserted_at > ago(^days, "day"))
    |> group_by([w], fragment("lower(?)", w.method))
    |> select([w], {fragment("lower(?)", w.method), count(w.id)})
    |> Repo.all(skip_organization_id: true)
  end

  @spec http_org_ids(pos_integer()) :: MapSet.t()
  defp http_org_ids(days) do
    WebhookLog
    |> where([w], like(w.url, "http%") and w.inserted_at > ago(^days, "day"))
    |> distinct(true)
    |> select([w], w.organization_id)
    |> Repo.all(skip_organization_id: true)
    |> MapSet.new()
  end

  @spec resume_dispatches_by_org(pos_integer()) :: [{non_neg_integer(), non_neg_integer()}]
  defp resume_dispatches_by_org(days) do
    WebhookLog
    |> where([w], w.url in @async_nodes and w.inserted_at > ago(^days, "day"))
    |> group_by([w], w.organization_id)
    |> select([w], {w.organization_id, count(w.id)})
    |> Repo.all(skip_organization_id: true)
  end

  @spec group_by_phrase([Organization.t()]) :: map()
  defp group_by_phrase(organizations) do
    Enum.group_by(organizations, fn organization ->
      cond do
        organization.signature_phrase in [nil, ""] -> :blank
        organization.signature_phrase in @known_defaults -> :still_default
        true -> :changed
      end
    end)
  end
end
