defmodule Glific.AI.WorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Request,
    AI.Usage,
    AI.Worker,
    Fixtures,
    Repo
  }

  defmodule RecordingProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(_messages, _opts) do
      # Captured inside the job, so the test can assert who the run acted as.
      send(:worker_test, {:ran_as, Glific.Repo.get_current_user()})
      {:ok, Message.assistant("an answer"), %Usage{cost: Decimal.new("0.002")}}
    end
  end

  setup do
    Process.register(self(), :worker_test)
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.put(original, :provider, RecordingProvider))
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)

    user = Fixtures.user_fixture(%{organization_id: 1})

    conversation =
      %Conversation{}
      |> Conversation.changeset(%{user_id: user.id, organization_id: 1})
      |> Repo.insert!()

    request =
      %Request{}
      |> Request.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        organization_id: 1,
        skill: "knowledge",
        status: :pending
      })
      |> Repo.insert!()

    %Event{}
    |> Event.changeset(%{
      request_id: request.id,
      conversation_id: conversation.id,
      organization_id: 1,
      step: 1,
      type: :user,
      content: "a question"
    })
    |> Repo.insert!()

    %{user: user, request: request}
  end

  test "the job runs the request and records the answer", %{user: user, request: request} do
    assert :ok =
             perform_job(Worker, %{"request_id" => request.id, "organization_id" => 1})

    request = Repo.reload!(request)
    assert request.status == :succeeded
    assert Decimal.equal?(request.cost, Decimal.new("0.002"))

    assert [%Event{type: :user}, %Event{type: :assistant, content: "an answer"}] =
             Event
             |> Ecto.Query.where([e], e.request_id == ^request.id)
             |> Ecto.Query.order_by([e], asc: e.step)
             |> Repo.all()

    assert_received {:ran_as, ran_as}
    assert ran_as.id == user.id
  end

  test "the job acts as the asker, not the organisation's root user", %{
    user: user,
    request: request
  } do
    root = Glific.Partners.organization(1).root_user
    refute root.id == user.id

    assert :ok = perform_job(Worker, %{"request_id" => request.id, "organization_id" => 1})

    assert_received {:ran_as, ran_as}
    assert ran_as.id == user.id
    refute ran_as.id == root.id
  end

  test "enqueue/1 schedules the request on the glific_ai queue", %{request: request} do
    assert {:ok, job} = Worker.enqueue(request)
    assert job.queue == "glific_ai"
    assert job.args["request_id"] == request.id
    assert job.max_attempts == 1
  end
end
