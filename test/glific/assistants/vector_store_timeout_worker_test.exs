defmodule Glific.Assistants.VectorStoreTimeoutWorkerTest do
  @moduledoc """
  Tests for VectorStoreTimeoutWorker
  """
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Assistants.VectorStoreTimeoutWorker,
    Notifications.Notification,
    Repo
  }

  describe "process_timeouts/1" do
    setup %{organization_id: org_id} do
      {kb, kbv} = create_knowledge_base_version(org_id, :in_progress, "job_123", hours_ago: 2)
      {assistant, acv} = create_assistant_with_config(org_id, :in_progress)
      link_kbv_to_acv(kbv, acv, org_id)

      [kb: kb, kbv: kbv, assistant: assistant, acv: acv]
    end

    test "marks timed-out KnowledgeBaseVersion as failed", %{organization_id: org_id, kbv: kbv} do
      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      {:ok, updated_kbv} = Repo.fetch_by(KnowledgeBaseVersion, %{id: kbv.id})
      assert updated_kbv.status == :failed
      assert updated_kbv.failure_reason =~ "timed out"
    end

    test "does NOT affect records less than 1 hour old", %{organization_id: org_id} do
      {_kb, kbv} = create_knowledge_base_version(org_id, :in_progress, "job_456", hours_ago: 0)

      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      {:ok, updated_kbv} = Repo.fetch_by(KnowledgeBaseVersion, %{id: kbv.id})
      assert updated_kbv.status == :in_progress
      assert updated_kbv.failure_reason == nil
    end

    test "ignores records that are already completed", %{organization_id: org_id} do
      {_kb, kbv} = create_knowledge_base_version(org_id, :completed, "job_456", hours_ago: 2)

      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      {:ok, updated_kbv} = Repo.fetch_by(KnowledgeBaseVersion, %{id: kbv.id})
      assert updated_kbv.status == :completed
      assert updated_kbv.failure_reason == nil
    end

    test "updates linked in_progress AssistantConfigVersions to failed", %{
      organization_id: org_id,
      acv: acv
    } do
      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      {:ok, updated_acv} = Repo.fetch_by(AssistantConfigVersion, %{id: acv.id})
      assert updated_acv.status == :failed
      assert updated_acv.failure_reason =~ "vector store creation timed out"
    end

    test "does NOT update linked ready AssistantConfigVersions", %{
      organization_id: org_id,
      kbv: kbv
    } do
      {_assistant, acv_ready} = create_assistant_with_config(org_id, :ready)
      link_kbv_to_acv(kbv, acv_ready, org_id)

      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      {:ok, updated_acv} = Repo.fetch_by(AssistantConfigVersion, %{id: acv_ready.id})
      assert updated_acv.status == :ready
      assert updated_acv.failure_reason == nil
    end

    test "creates notification with correct details", %{
      organization_id: org_id,
      kb: kb,
      kbv: kbv
    } do
      initial_count = Repo.aggregate(Notification, :count, :id)

      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      assert Repo.aggregate(Notification, :count, :id) == initial_count + 1

      notification =
        Notification
        |> where([n], n.organization_id == ^org_id)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      assert notification.category == "Assistant"
      assert notification.severity == "Warning"
      assert notification.message =~ kb.name
      assert notification.message =~ "timed out"
      assert notification.entity["knowledge_base_version_id"] == kbv.id
      assert notification.entity["kaapi_job_id"] == "job_123"
    end

    test "notification includes affected assistant names", %{
      organization_id: org_id,
      assistant: assistant,
      acv: acv
    } do
      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      notification =
        Notification
        |> where([n], n.organization_id == ^org_id)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      assert notification.message =~ assistant.name
      assert notification.entity["affected_config_version_ids"] == [acv.id]
    end

    test "processes multiple timed-out records", %{organization_id: org_id, kbv: kbv1} do
      {_kb2, kbv2} = create_knowledge_base_version(org_id, :in_progress, "job_2", hours_ago: 3)

      assert :ok = VectorStoreTimeoutWorker.process_timeouts(org_id)

      {:ok, updated_kbv1} = Repo.fetch_by(KnowledgeBaseVersion, %{id: kbv1.id})
      {:ok, updated_kbv2} = Repo.fetch_by(KnowledgeBaseVersion, %{id: kbv2.id})

      assert updated_kbv1.status == :failed
      assert updated_kbv2.status == :failed
    end
  end

  defp create_knowledge_base_version(org_id, status, kaapi_job_id, opts) do
    hours_ago = Keyword.get(opts, :hours_ago, 0)

    {:ok, kb} =
      %KnowledgeBase{}
      |> KnowledgeBase.changeset(%{
        name: "Test Knowledge Base #{:rand.uniform(10000)}",
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, kbv} =
      %KnowledgeBaseVersion{}
      |> KnowledgeBaseVersion.changeset(%{
        knowledge_base_id: kb.id,
        organization_id: org_id,
        files: %{"file1.pdf" => %{"size" => 1024}},
        status: status,
        llm_service_id: "vs_test_#{:rand.uniform(10000)}",
        kaapi_job_id: kaapi_job_id
      })
      |> Repo.insert()

    if hours_ago > 0 do
      past_time = DateTime.utc_now() |> DateTime.add(-hours_ago * 3600, :second)

      KnowledgeBaseVersion
      |> where([kbv], kbv.id == ^kbv.id)
      |> Repo.update_all(set: [inserted_at: past_time])
    end

    {:ok, refreshed} = Repo.fetch_by(KnowledgeBaseVersion, %{id: kbv.id})
    {kb, refreshed}
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
        settings: %{"temperature" => 1.0},
        status: status
      })
      |> Repo.insert()

    {assistant, config_version}
  end

  defp link_kbv_to_acv(kbv, acv, org_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: acv.id,
        knowledge_base_version_id: kbv.id,
        organization_id: org_id,
        inserted_at: now,
        updated_at: now
      }
    ])
  end
end
