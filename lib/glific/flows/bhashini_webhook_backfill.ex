defmodule Glific.Flows.BhashiniWebhookBackfill do
  @moduledoc """
  One-shot, idempotent backfill that removes the deprecated Bhashini "Speech to
  Text" / "Text to Speech" **template** flows from every organization that
  imported them at onboarding and re-imports the new Kaapi-based
  `speech_to_text.json` / `text_to_speech.json` templates in their place.

  Bhashini is fully removed from Glific: the `*_with_bhasini` FUNCTION webhooks
  are gone (publishing a flow that references one now raises a "Critical"
  validation error, see `Glific.Flows.Action`'s `@deprecated_bhashini_webhooks`),
  and the shipped templates were rewritten onto the async Kaapi nodes. This
  backfill brings already-onboarded orgs in line — it **deletes** their old
  Bhashini template flow (name and all) and gives them the **fresh** template, so
  no trace of Bhashini is left in their flow list.

  ## Scope: template flows only

  Only flows with `is_template = true` that still reference a deprecated Bhashini
  webhook are touched. Custom flows are never deleted or modified — the
  deprecation was announced months ago and no organization uses these webhooks in
  their own flows. Because a template flow cannot be used as a sub-flow, deleting
  and re-importing it cannot break any `enter_flow` reference.

  ## Idempotency / safety

  For each affected org we import the new template first (skipping it if a flow
  with that name already exists) and only then delete the Bhashini template, so a
  partial re-run never duplicates a template and never leaves an org without one.
  A completed org no longer has a Bhashini template, so it is not re-selected.

  Run from the `20260701000000_backfill_deprecated_bhashini_webhooks.exs`
  migration via `run/0`.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Glific.{
    Flows,
    Flows.Flow,
    Flows.FlowRevision,
    Partners,
    Partners.Organization,
    Repo,
    Seeds.SeedsFlows,
    Users.User
  }

  @deprecated_webhooks [
    "speech_to_text_with_bhasini",
    "text_to_speech_with_bhasini",
    "nmt_tts_with_bhasini"
  ]

  # New template file -> the flow name it imports as (used for the idempotency guard).
  @new_templates [
    {"speech_to_text.json", "Speech to Text"},
    {"text_to_speech.json", "Text to Speech"}
  ]

  @doc """
  Cross-org entry point. For every organization that still has a Bhashini template
  flow, re-import the new STT/TTS templates and delete the Bhashini ones.
  """
  @spec run() :: :ok
  def run do
    organizations_with_bhashini_templates()
    |> Enum.each(&replace_templates/1)
  end

  @spec organizations_with_bhashini_templates() :: [non_neg_integer()]
  defp organizations_with_bhashini_templates do
    from(fr in FlowRevision,
      join: flow in Flow,
      on: flow.id == fr.flow_id,
      where: flow.is_template == true,
      where: fragment("?::text ~ ?", fr.definition, ^deprecated_pattern()),
      distinct: true,
      select: flow.organization_id
    )
    |> Repo.all(skip_organization_id: true)
  end

  @spec replace_templates(non_neg_integer()) :: :ok
  defp replace_templates(organization_id) do
    case pick_user(organization_id) do
      nil ->
        Glific.log_error(
          "BhashiniWebhookBackfill: no user found for organization #{organization_id}, skipping",
          false
        )

      %User{} = user ->
        organization = Partners.organization(organization_id)
        Repo.put_organization_id(organization_id)
        Repo.put_current_user(user)

        import_new_templates(organization)
        delete_bhashini_templates(organization_id)
    end

    :ok
  end

  @spec import_new_templates(Organization.t()) :: :ok
  defp import_new_templates(organization) do
    Enum.each(@new_templates, fn {flow_file, flow_name} ->
      # Guard so a re-run (or an org that already has the new template) never
      # imports a duplicate.
      unless template_present?(organization.id, flow_name) do
        SeedsFlows.import_template_flow(organization, flow_file)
      end
    end)
  end

  @spec delete_bhashini_templates(non_neg_integer()) :: :ok
  defp delete_bhashini_templates(organization_id) do
    from(flow in Flow,
      join: fr in FlowRevision,
      on: fr.flow_id == flow.id,
      where: flow.organization_id == ^organization_id,
      where: flow.is_template == true,
      where: fragment("?::text ~ ?", fr.definition, ^deprecated_pattern()),
      distinct: true
    )
    |> Repo.all()
    |> Enum.each(&Flows.delete_flow/1)
  end

  @spec template_present?(non_neg_integer(), String.t()) :: boolean()
  defp template_present?(organization_id, flow_name) do
    Repo.exists?(
      from(flow in Flow,
        where: flow.organization_id == ^organization_id and flow.name == ^flow_name
      )
    )
  end

  @spec pick_user(non_neg_integer()) :: User.t() | nil
  defp pick_user(organization_id) do
    Repo.one(
      from(user in User,
        where: user.organization_id == ^organization_id,
        limit: 1
      ),
      skip_organization_id: true
    )
  end

  @spec deprecated_pattern() :: String.t()
  defp deprecated_pattern, do: Enum.map_join(@deprecated_webhooks, "|", &Regex.escape/1)
end
