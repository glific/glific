defmodule Glific.Scripts.BhashiniTemplateMigration do
  @moduledoc """
  Admin script that migrates organizations off the deprecated Bhashini
  "Speech to Text" / "Text to Speech" **template** flows onto the new
  Kaapi-based templates.

  Bhashini is fully removed from Glific: the `*_with_bhasini` FUNCTION
  webhooks no longer exist (publishing a flow that references one raises a
  "Critical" validation error), and the shipped templates were rewritten onto
  the async Kaapi nodes (`speech_to_text` / `text_to_speech`). This script
  brings already-onboarded organizations in line: it imports the new
  templates first and only then deletes the deprecated Bhashini template
  flow(s), so an organization is never left without a template.

  Run from the remote IEx console (e.g. `gigalixir remote_console`), with the
  app fully booted so Cachex / the supervision tree are up — this is the
  whole reason this lives here instead of in an Ecto migration.

      # Preview affected flows only, makes NO writes:
      Glific.Scripts.BhashiniTemplateMigration.run(dry_run: true)

      # Migrate a single organization first, to sanity check:
      Glific.Scripts.BhashiniTemplateMigration.run(organization_id: 123)

      # Migrate every affected organization:
      Glific.Scripts.BhashiniTemplateMigration.run()

  ## Scope: the two shipped Bhashini template flows, matched by name

  Only flows with `is_template == true` whose name is one of the two seeded
  Bhashini templates (`Bhashini_speech_to_text`, `Bhashini_TextToSpeech`) are
  targeted. Those are the only flows that ever used the Bhashini webhooks — no
  other template (nor any custom flow) references them — so matching the seeded
  flow name is enough and there is no need to parse every template's revision.
  Custom (non-template) flows are never touched.

  ## Safety

  For each affected organization: the two new templates are imported first,
  skipped when a flow with that name **and** `is_template == true` already
  exists. The deprecated Bhashini flow(s) are deleted **only if both new
  templates are confirmed present** after that step. If a template import
  fails, the organization is logged and skipped for deletion — it is never
  left without a template.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Flows,
    Flows.Flow,
    Partners,
    Partners.Organization,
    Repo,
    Seeds.SeedsFlows,
    Users.User
  }

  # The two template flows that shipped with the deprecated Bhashini webhooks,
  # matched by their exact seeded flow name. These are the only flows that ever
  # used Bhashini (verified against every template JSON in priv/data/flows), so
  # matching the name is sufficient and avoids parsing every template's revision.
  @deprecated_flow_names ["Bhashini_speech_to_text", "Bhashini_TextToSpeech"]

  # New template file -> the flow name it imports as (used for the
  # is_template-scoped idempotency guard).
  @new_templates [
    {"speech_to_text.json", "Speech to Text"},
    {"text_to_speech.json", "Text to Speech"}
  ]

  @type opts :: [dry_run: boolean(), organization_id: pos_integer()]

  @doc """
  Entry point.

    * `dry_run: true` — only prints a table of the deprecated template flows
      that would be migrated; makes no writes.
    * `organization_id: id` — process only that one organization.
    * no opts — process every affected organization.
  """
  @spec run(opts()) :: :ok
  def run(opts \\ []) do
    flows = deprecated_template_flows(opts)

    if Keyword.get(opts, :dry_run, false) do
      print_dry_run(flows)
    else
      flows
      |> Enum.group_by(& &1.organization_id)
      |> Enum.each(fn {organization_id, org_flows} ->
        migrate_organization(organization_id, org_flows)
      end)
    end

    :ok
  end

  @spec print_dry_run([Flow.t()]) :: :ok
  defp print_dry_run(flows) do
    IO.puts("index | organization_id | flow_id | flow_name")

    flows
    |> Enum.with_index(1)
    |> Enum.each(fn {flow, index} ->
      IO.puts("#{index} | #{flow.organization_id} | #{flow.id} | #{flow.name}")
    end)

    :ok
  end

  @spec migrate_organization(non_neg_integer(), [Flow.t()]) :: :ok
  defp migrate_organization(organization_id, deprecated_flows) do
    Repo.put_organization_id(organization_id)

    case fetch_org_and_user(organization_id) do
      {:ok, organization, user} ->
        Repo.put_current_user(user)
        ensure_templates_then_delete(organization, deprecated_flows)

      {:error, reason} ->
        Glific.log_error(
          "BhashiniTemplateMigration: skipping organization #{organization_id}, #{reason}",
          false
        )
    end

    :ok
  end

  @spec ensure_templates_then_delete(Organization.t(), [Flow.t()]) :: :ok
  defp ensure_templates_then_delete(organization, deprecated_flows) do
    case ensure_new_templates(organization) do
      :ok ->
        Enum.each(deprecated_flows, &delete_deprecated_flow/1)

      {:error, reason} ->
        Glific.log_error(
          "BhashiniTemplateMigration: skipping deletion for organization #{organization.id}, " <>
            "template import failed: #{reason}",
          false
        )
    end

    :ok
  end

  # Fetches the organization and picks its admin user context, the same way
  # `Repo.put_process_state/1` does for Oban workers: the organization's
  # `root_user` (the user tied to the org's root contact). Never crashes on a
  # missing organization / missing user — always returns a tagged tuple so
  # the caller can log + skip.
  @spec fetch_org_and_user(non_neg_integer()) ::
          {:ok, Organization.t(), User.t()} | {:error, String.t()}
  defp fetch_org_and_user(organization_id) do
    case Partners.organization(organization_id) do
      %Organization{root_user: %User{} = user} = organization ->
        {:ok, organization, user}

      %Organization{} ->
        {:error, "no user found for organization #{organization_id}"}

      {:error, reason} ->
        {:error,
         "could not load organization #{organization_id}: #{Glific.SafeLog.safe_inspect(reason)}"}

      nil ->
        {:error, "organization #{organization_id} not found"}
    end
  rescue
    error ->
      {:error, "could not load organization #{organization_id}: #{Exception.message(error)}"}
  end

  @spec ensure_new_templates(Organization.t()) :: :ok | {:error, String.t()}
  defp ensure_new_templates(organization) do
    Enum.reduce_while(@new_templates, :ok, fn {file, name}, :ok ->
      case ensure_template(organization, file, name) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec ensure_template(Organization.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  defp ensure_template(organization, file, name) do
    if template_present?(organization.id, name) do
      :ok
    else
      case SeedsFlows.import_template_flow(organization, file) do
        {:ok, _flow} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Guard is scoped to `is_template == true` so a pre-existing *custom* flow
  # that happens to share the template's name never suppresses the import.
  @spec template_present?(non_neg_integer(), String.t()) :: boolean()
  defp template_present?(organization_id, name) do
    Repo.exists?(
      from(flow in Flow,
        where:
          flow.organization_id == ^organization_id and
            flow.name == ^name and
            flow.is_template == true
      )
    )
  end

  @spec delete_deprecated_flow(Flow.t()) :: :ok
  defp delete_deprecated_flow(flow) do
    case Flows.delete_flow(flow) do
      {:ok, _flow} ->
        :ok

      {:error, changeset} ->
        Glific.log_error(
          "BhashiniTemplateMigration: failed to delete deprecated flow #{flow.id} " <>
            "(org #{flow.organization_id}): #{Glific.SafeLog.safe_inspect(changeset.errors)}",
          false
        )
    end

    :ok
  end

  @spec deprecated_template_flows(opts()) :: [Flow.t()]
  defp deprecated_template_flows(opts) do
    organization_id = Keyword.get(opts, :organization_id)

    Flow
    |> where([flow], flow.is_template == true and flow.name in @deprecated_flow_names)
    |> filter_organization(organization_id)
    |> Repo.all(skip_organization_id: true)
  end

  @spec filter_organization(Ecto.Query.t(), pos_integer() | nil) :: Ecto.Query.t()
  defp filter_organization(query, nil), do: query

  defp filter_organization(query, organization_id),
    do: where(query, [flow], flow.organization_id == ^organization_id)
end
