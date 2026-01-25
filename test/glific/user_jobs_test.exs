defmodule Glific.UserJobTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Jobs.UserJob,
    Jobs.UserJobWorker
  }

  setup do
    organization = Fixtures.organization_fixture()
    {:ok, organization: organization}
  end

  describe "UserJob" do
    @valid_attrs %{
      status: "pending",
      type: "import",
      total_tasks: 10,
      tasks_done: 0,
      organization_id: 1,
      all_tasks_created: false
    }

    @update_attrs %{
      status: "completed",
      tasks_done: 10,
      all_tasks_created: true
    }

    def user_job_fixture(attrs \\ %{}) do
      attrs
      |> Enum.into(@valid_attrs)
      |> UserJob.create_user_job()
    end

    test "list_user_jobs/1 returns all user_jobs", %{organization: organization} do
      user_job_fixture(organization_id: organization.id)
      user_jobs = UserJob.list_user_jobs(%{filter: %{organization_id: organization.id}})
      assert length(user_jobs) == 1
    end

    test "create_user_job/1 with valid data creates a user_job", %{organization: organization} do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization.id})

      user_job = UserJob.create_user_job(attrs)

      assert user_job.status == "pending"
      assert user_job.type == "import"
      assert user_job.total_tasks == 10
      assert user_job.tasks_done == 0
      assert user_job.organization_id == organization.id
      assert user_job.all_tasks_created == false
    end

    test "update_user_job/2 with valid data updates the user_job", %{organization: organization} do
      user_job = user_job_fixture(organization_id: organization.id)

      assert {:ok, %UserJob{} = user_job} =
               UserJob.update_user_job(user_job, @update_attrs)

      assert user_job.status == "completed"
      assert user_job.tasks_done == 10
      assert user_job.all_tasks_created == true
    end

    test "updates the status to success for jobs with all tasks done", %{
      organization: organization
    } do
      attrs = %{
        status: "pending",
        type: "import",
        total_tasks: 10,
        tasks_done: 10,
        organization_id: organization.id,
        all_tasks_created: true
      }

      UserJob.create_user_job(attrs)

      assert :ok == UserJobWorker.check_user_job_status(organization.id)
      user_job = UserJob.list_user_jobs(%{filter: %{organization_id: organization.id}})
      success_jobs = Enum.filter(user_job, &(&1.status == "success"))
      assert length(success_jobs) == 1
    end
  end
end
