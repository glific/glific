defmodule Glific.Scripts.Evals do
  @moduledoc """
  Admin helper scripts for AI Evaluations.

  Run from the remote IEx console (e.g. `gigalixir remote_console`):

      Glific.Scripts.Evals.approve_eval_access_with_langfuse(
        org_id,
        "pk-lf-...",
        "sk-lf-...",
        "https://cloud.langfuse.com"
      )

  """

  alias Glific.{
    AIEvaluations.OrganizationEvalRequest,
    Partners,
    Repo,
    ThirdParty.Discord.Notifications,
    ThirdParty.Kaapi,
    ThirdParty.Kaapi.ApiClient
  }

  @doc """
  Inserts Langfuse credentials into Kaapi and approves the eval access request
  for an organization.
  """
  @spec approve_eval_access_with_langfuse(
          non_neg_integer(),
          String.t(),
          String.t(),
          String.t()
        ) :: :ok
  def approve_eval_access_with_langfuse(
        org_id,
        langfuse_public_key,
        langfuse_secret_key,
        langfuse_host
      ) do
    Repo.put_organization_id(org_id)

    case Repo.fetch_by(OrganizationEvalRequest, %{organization_id: org_id}) do
      {:error, _} ->
        IO.puts("✗ No eval access request found for org_id: #{org_id}")
        IO.puts("  Ask the org to request access from the Glific dashboard first.")

      {:ok, %OrganizationEvalRequest{status: "approved"} = request} ->
        IO.puts("Already approved (id: #{request.id}), skipping.")

      {:ok, request} ->
        insert_langfuse_creds(org_id, langfuse_public_key, langfuse_secret_key, langfuse_host)
        approve_request(request, org_id)
    end
  end

  @spec insert_langfuse_creds(non_neg_integer(), String.t(), String.t(), String.t()) :: :ok
  defp insert_langfuse_creds(org_id, langfuse_public_key, langfuse_secret_key, langfuse_host) do
    {:ok, secrets} = Kaapi.fetch_kaapi_creds(org_id)

    case ApiClient.update_organization_credentials(
           %{
             provider: "langfuse",
             credential: %{
               langfuse: %{
                 public_key: langfuse_public_key,
                 secret_key: langfuse_secret_key,
                 host: langfuse_host
               }
             },
             is_active: true
           },
           secrets["api_key"]
         ) do
      {:ok, _} ->
        IO.puts("✓ Langfuse credentials inserted successfully")

      {:error, reason} ->
        IO.puts("✗ Failed: #{Glific.SafeLog.safe_inspect(reason)}")
        raise "Aborting: Langfuse credential insert failed"
    end
  end

  @spec approve_request(OrganizationEvalRequest.t(), non_neg_integer()) :: :ok
  defp approve_request(request, org_id) do
    case request
         |> OrganizationEvalRequest.changeset(%{status: "approved"})
         |> Repo.update() do
      {:ok, updated} ->
        IO.puts("✓ Eval access approved (id: #{updated.id})")
        organization = Partners.organization(org_id)
        Notifications.send_eval_access_approved(organization)

      {:error, changeset} ->
        IO.puts("✗ Failed: #{Glific.SafeLog.safe_inspect(changeset.errors)}")
    end
  end
end
