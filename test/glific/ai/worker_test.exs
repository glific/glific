defmodule Glific.AI.WorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Worker,
    FakeProvider,
    Fixtures,
    Repo
  }

  setup do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.merge(original, FakeProvider.start()))

    on_exit(fn ->
      FakeProvider.stop()
      Application.put_env(:glific, Glific.AI, original)
    end)

    FakeProvider.always(FakeProvider.answer("an answer"))

    # AI.generate/3 checks the flag on every call, and FunWithFlags state is
    # global, so set it here rather than inheriting whatever ran before.
    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

    user = Fixtures.user_fixture(%{organization_id: 1})

    conversation =
      %Conversation{}
      |> Conversation.changeset(%{user_id: user.id, organization_id: 1})
      |> Repo.insert!()

    request =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        organization_id: 1,
        skill: "knowledge",
        status: :pending
      })
      |> Repo.insert!()

    %Event{}
    |> Event.changeset(%{
      message_id: request.id,
      conversation_id: conversation.id,
      organization_id: 1,
      step: 1,
      type: :user,
      content: "a question"
    })
    |> Repo.insert!()

    %{user: user, request: request}
  end

  test "the job runs the request and records the answer", %{request: request} do
    assert :ok =
             perform_job(Worker, %{"message_id" => request.id, "organization_id" => 1})

    request = Repo.reload!(request)
    assert request.status == :succeeded
    assert Decimal.gt?(request.cost, 0)

    # The question and the answer, whatever routing did in between: which skill
    # was chosen is `Glific.AI.SkillRunTest`'s business, not the worker's.
    assert [%Event{type: :user}, %Event{type: :assistant, content: "an answer"}] =
             Event
             |> Ecto.Query.where(
               [e],
               e.message_id == ^request.id and e.type in [:user, :assistant]
             )
             |> Ecto.Query.order_by([e], asc: e.step)
             |> Repo.all()
  end

  test "the job acts as the asker, not the organisation's root user", %{
    user: user,
    request: request
  } do
    root = Glific.Partners.organization(1).root_user
    refute root.id == user.id

    # Someone else is installed before the job runs, so the assertion below is
    # about what the worker did rather than what the test set up.
    refute Repo.get_current_user().id == user.id

    assert :ok = perform_job(Worker, %{"message_id" => request.id, "organization_id" => 1})

    assert Repo.get_current_user().id == user.id
    refute Repo.get_current_user().id == root.id
  end

  test "enqueue/1 schedules the request on the glific_ai queue", %{request: request} do
    assert {:ok, job} = Worker.enqueue(request)
    assert job.queue == "glific_ai"
    assert job.args["message_id"] == request.id
    assert job.max_attempts == 1
  end
end
