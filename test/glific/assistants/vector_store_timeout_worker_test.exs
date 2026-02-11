defmodule Glific.AssistantsTimeoutTest do
  @moduledoc """
  Tests for process_timeouts in Glific.Assistants
  """
  use Glific.DataCase

  import Ecto.Query

  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Notifications.Notification
  alias Glific.Repo

  describe "process_timeouts/1" do
    setup %{organization_id: org_id} do
      {knowledge_base, knowledge_base_version} =
        create_knowledge_base_version(org_id, :in_progress, "job_123", hours_ago: 2)

      {assistant, config_version} = create_assistant_with_config(org_id, :in_progress)
      link_kbv_to_acv(knowledge_base_version, config_version, org_id)

      [
        knowledge_base: knowledge_base,
        knowledge_base_version: knowledge_base_version,
        assistant: assistant,
        config_version: config_version
      ]
    end

    test "marks timed-out KnowledgeBaseVersion as failed", %{
      organization_id: org_id,
      knowledge_base_version: knowledge_base_version
    } do
      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv} = Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})
      assert updated_kbv.status == :failed
    end

    test "does NOT affect records less than 1 hour old", %{organization_id: org_id} do
      {_knowledge_base, knowledge_base_version} =
        create_knowledge_base_version(org_id, :in_progress, "job_456", hours_ago: 0)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})
      assert updated_kbv.status == :in_progress
    end

    test "ignores records that are already completed", %{organization_id: org_id} do
      {_knowledge_base, knowledge_base_version} =
        create_knowledge_base_version(org_id, :completed, "job_456", hours_ago: 2)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})
      assert updated_kbv.status == :completed
    end

    test "updates linked in_progress AssistantConfigVersions to failed", %{
      organization_id: org_id,
      config_version: config_version
    } do
      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_acv} = Repo.fetch_by(AssistantConfigVersion, %{id: config_version.id})
      assert updated_acv.status == :failed
      assert updated_acv.failure_reason =~ "vector store creation timed out"
    end

    test "does NOT update linked ready AssistantConfigVersions", %{
      organization_id: org_id,
      knowledge_base_version: knowledge_base_version
    } do
      {_assistant, acv_ready} = create_assistant_with_config(org_id, :ready)
      link_kbv_to_acv(knowledge_base_version, acv_ready, org_id)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_acv} = Repo.fetch_by(AssistantConfigVersion, %{id: acv_ready.id})
      assert updated_acv.status == :ready
      assert updated_acv.failure_reason == nil
    end

    test "creates notification with correct details", %{
      organization_id: org_id,
      knowledge_base: knowledge_base,
      knowledge_base_version: knowledge_base_version
    } do
      initial_count = Repo.aggregate(Notification, :count, :id)

      assert :ok = Assistants.process_timeouts(org_id)

      assert Repo.aggregate(Notification, :count, :id) == initial_count + 1

      notification =
        Notification
        |> where([n], n.organization_id == ^org_id)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      assert notification.category == "Assistant"
      assert notification.severity == "Warning"
      assert notification.message =~ knowledge_base.name
      assert notification.message =~ "timed out"
      assert notification.entity["knowledge_base_version_id"] == knowledge_base_version.id
      assert notification.entity["kaapi_job_id"] == "job_123"
    end

    test "notification includes affected assistant names", %{
      organization_id: org_id,
      assistant: assistant,
      config_version: config_version
    } do
      assert :ok = Assistants.process_timeouts(org_id)

      notification =
        Notification
        |> where([n], n.organization_id == ^org_id)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      assert notification.message =~ assistant.name
      assert notification.entity["affected_config_version_ids"] == [config_version.id]
    end

    test "processes multiple timed-out records", %{
      organization_id: org_id,
      knowledge_base_version: knowledge_base_version_1
    } do
      {_knowledge_base_2, knowledge_base_version_2} =
        create_knowledge_base_version(org_id, :in_progress, "job_2", hours_ago: 3)

      assert :ok = Assistants.process_timeouts(org_id)

      {:ok, updated_kbv_1} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version_1.id})

      {:ok, updated_kbv_2} =
        Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version_2.id})

      assert updated_kbv_1.status == :failed
      assert updated_kbv_2.status == :failed
    end
  end

  defp create_knowledge_base_version(org_id, status, kaapi_job_id, opts) do
    hours_ago = Keyword.get(opts, :hours_ago, 0)

    {:ok, knowledge_base} =
      %KnowledgeBase{}
      |> KnowledgeBase.changeset(%{
        name: "Test Knowledge Base #{:rand.uniform(10000)}",
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, knowledge_base_version} =
      %KnowledgeBaseVersion{}
      |> KnowledgeBaseVersion.changeset(%{
        knowledge_base_id: knowledge_base.id,
        organization_id: org_id,
        files: %{"file1.pdf" => %{"size" => 1024}},
        status: status,
        llm_service_id: "vs_test_#{:rand.uniform(10000)}",
        kaapi_job_id: kaapi_job_id
      })
      |> Repo.insert()

    if hours_ago > 0 do
      past_time = DateTime.utc_now() |> DateTime.add(-hours_ago, :hour)

      KnowledgeBaseVersion
      |> where([kbv], kbv.id == ^knowledge_base_version.id)
      |> Repo.update_all(set: [inserted_at: past_time])
    end

    {:ok, refreshed} = Repo.fetch_by(KnowledgeBaseVersion, %{id: knowledge_base_version.id})
    {knowledge_base, refreshed}
  end

  defp create_assistant_with_config(org_id, status) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant #{:rand.uniform(10000)}",
        organization_id: org_id,
        kaapi_uuid: "asst_#{:rand.uniform(10000)}"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        organization_id: org_id,
        provider: "openai",
        model: "gpt-4o",
        prompt: "You are a helpful assistant",
        kaapi_uuid: "acv_#{:rand.uniform(10000)}",
        settings: %{"temperature" => 1.0},
        status: status
      })
      |> Repo.insert()

    {assistant, config_version}
  end

  defp link_kbv_to_acv(knowledge_base_version, config_version, org_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: knowledge_base_version.id,
        organization_id: org_id,
        inserted_at: now,
        updated_at: now
      }
    ])
  end
end
