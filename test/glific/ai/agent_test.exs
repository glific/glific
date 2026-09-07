defmodule Glific.AI.AgentTest do
  use Glific.DataCase

  import Ecto.Query

  alias FunWithFlags.Store.Cache

  alias Glific.{
    AI.Agent,
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Tools,
    FakeProvider,
    Fixtures,
    Repo
  }

  defp set_limits(limits) do
    original = Application.get_env(:glific, Agent, [])
    Application.put_env(:glific, Agent, Keyword.merge(original, limits))
    on_exit(fn -> Application.put_env(:glific, Agent, original) end)
  end

  defp ask(question, user, conversation \\ nil) do
    conversation =
      conversation ||
        %Conversation{}
        |> Conversation.changeset(%{user_id: user.id, organization_id: user.organization_id})
        |> Repo.insert!()

    request =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        organization_id: user.organization_id,
        skill: "knowledge",
        status: :running
      })
      |> Repo.insert!()

    %Event{}
    |> Event.changeset(%{
      message_id: request.id,
      conversation_id: conversation.id,
      organization_id: user.organization_id,
      step: 1,
      type: :user,
      content: question
    })
    |> Repo.insert!()

    {conversation, request}
  end

  setup do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.merge(original, FakeProvider.start()))

    on_exit(fn ->
      FakeProvider.stop()
      Application.put_env(:glific, Glific.AI, original)
    end)

    # AI.generate/3 checks the flag on every call, and FunWithFlags state is
    # global, so set it here rather than inheriting whatever ran before.
    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

    # The flag row is rolled back with the transaction, but its ETS cache is not,
    # so a later test that expects the flag off would read a stale true. Only the
    # cache is flushed here: `on_exit` runs after the sandbox connection is
    # checked in, so it cannot touch the database.
    on_exit(fn -> Cache.flush() end)

    Fixtures.flow_fixture(%{organization_id: 1, name: "Registration flow"})
    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  defp last_request, do: FakeProvider.seen() |> List.last() |> Jason.decode!()

  test "the model can read data before answering, and every step is recorded", %{user: user} do
    FakeProvider.script([
      FakeProvider.tool_use("list_flows", %{"name" => "Reg"}),
      FakeProvider.answer("You have one flow called Registration flow.")
    ])

    {_conversation, request} = ask("what flows do I have?", user)

    assert {:ok, answer, _meta} = Agent.run(request, user, skill: "knowledge")
    assert answer =~ "Registration flow"

    assert [
             {1, :user, _},
             {2, :tool_call, "list_flows"},
             {3, :tool_result, nil},
             {4, :assistant, _}
           ] =
             Event
             |> where([e], e.message_id == ^request.id)
             |> order_by([e], asc: e.step)
             |> select([e], {e.step, e.type, e.content})
             |> Repo.all()

    # The tool actually ran: its output is on the tool_result event.
    result = Repo.one(from(e in Event, where: e.type == :tool_result, select: e.data))
    assert result["output"] =~ "Registration flow"
  end

  test "several tools asked for at once all run, with unique ordered steps", %{user: user} do
    FakeProvider.script([
      FakeProvider.tool_uses([
        {"list_flows", %{}},
        {"list_templates", %{}},
        {"list_reference", %{"kind" => "tags"}}
      ]),
      FakeProvider.answer("Here is what I found.")
    ])

    {_conversation, request} = ask("tell me everything", user)

    assert {:ok, _, _meta} = Agent.run(request, user, skill: "knowledge")

    events =
      Event
      |> where([e], e.message_id == ^request.id)
      |> order_by([e], asc: e.step)
      |> select([e], {e.step, e.type, e.content})
      |> Repo.all()

    # 1 question + three tool round trips (two events each) + the answer.
    assert [
             {1, :user, _},
             {2, :tool_call, "list_flows"},
             {3, :tool_result, nil},
             {4, :tool_call, "list_templates"},
             {5, :tool_result, nil},
             {6, :tool_call, "list_reference"},
             {7, :tool_result, nil},
             {8, :assistant, "Here is what I found."}
           ] = events

    steps = Enum.map(events, &elem(&1, 0))
    assert steps == Enum.uniq(steps)
  end

  test "cost and outcome are recorded on the request", %{user: user} do
    FakeProvider.script([FakeProvider.answer("a short answer")])

    {_conversation, request} = ask("hello", user)
    assert {:ok, _, _meta} = Agent.run(request, user, skill: "knowledge")

    request = Repo.reload!(request)
    assert request.status == :succeeded
    assert request.input_tokens == 10
    assert request.output_tokens == 5
    # Cost comes from req_llm's own per-model pricing, so assert it was recorded
    # rather than pinning a number that changes when pricing does.
    assert Decimal.gt?(request.cost, 0)
    assert request.model
  end

  test "a follow-up carries the earlier exchange", %{user: user} do
    FakeProvider.script([FakeProvider.answer("An HSM is a template message.")])

    {conversation, first} = ask("what is an HSM?", user)
    assert {:ok, _, _meta} = Agent.run(first, user, skill: "knowledge")

    FakeProvider.script([FakeProvider.answer("You send one from a flow.")])
    {_, second} = ask("how do I send one?", user, conversation)
    assert {:ok, _, _meta} = Agent.run(second, user, skill: "knowledge")

    sent = last_request()

    # Anthropic carries the system prompt out of band, so it is not a message.
    assert is_binary(sent["system"])

    assert Enum.map(sent["messages"], & &1["role"]) == ["user", "assistant", "user"]

    assert Enum.map(sent["messages"], & &1["content"]) == [
             "what is an HSM?",
             "An HSM is a template message.",
             "how do I send one?"
           ]
  end

  test "a turn cannot spend more steps than the budget has left", %{user: user} do
    # Two steps per call and a budget of four, so only two of the three asked
    # for may run. Without a reservation the whole turn would start and spend
    # six.
    set_limits(max_steps: 4)

    FakeProvider.always(
      FakeProvider.tool_uses([
        {"list_flows", %{}},
        {"list_templates", %{}},
        {"list_reference", %{"kind" => "tags"}}
      ])
    )

    {_conversation, request} = ask("tell me everything", user)

    assert {:error, reason} = Agent.run(request, user, skill: "knowledge")
    assert reason =~ "limit of 4 steps"

    spent =
      Event
      |> where([e], e.message_id == ^request.id and e.type in [:tool_call, :tool_result])
      |> Repo.aggregate(:count)

    assert spent == 4
  end

  test "a tool whose task dies is recorded, and not reported as a timeout", %{user: user} do
    FakeProvider.script([
      FakeProvider.tool_use("list_flows", %{}),
      FakeProvider.answer("done")
    ])

    {_conversation, request} = ask("what flows do I have?", user)

    assert {:ok, _, _meta} = Agent.run(request, user, skill: "knowledge")

    # Every call has a terminal result, whatever happened to the task that ran
    # it, so the trail never shows a call with no outcome.
    calls =
      Event
      |> where([e], e.message_id == ^request.id and e.type == :tool_call)
      |> select([e], e.tool_call_id)
      |> Repo.all()

    results =
      Event
      |> where([e], e.message_id == ^request.id and e.type == :tool_result)
      |> select([e], e.tool_call_id)
      |> Repo.all()

    assert Enum.sort(calls) == Enum.sort(results)
  end

  test "a model that keeps calling tools is stopped by the step limit", %{user: user} do
    FakeProvider.always(FakeProvider.tool_use("list_flows"))
    set_limits(max_steps: 6)

    {_conversation, request} = ask("loop forever", user)

    assert {:error, reason} = Agent.run(request, user, skill: "knowledge")
    assert reason =~ "limit of 6 steps"

    request = Repo.reload!(request)
    assert request.status == :failed
    assert request.error =~ "6 steps"

    # Exactly the budget that was set: two events per tool call, three calls.
    spent =
      Event
      |> where([e], e.message_id == ^request.id and e.type in [:tool_call, :tool_result])
      |> Repo.aggregate(:count)

    assert spent == 6
  end

  test "a run is stopped by the cost ceiling", %{user: user} do
    FakeProvider.always(FakeProvider.tool_use("list_flows"))
    # A real call costs fractions of a cent, so the ceiling is set below one call
    # rather than inventing an implausible price.
    set_limits(max_cost_usd: "0.00001", max_steps: 50)

    {_conversation, request} = ask("expensive question", user)

    assert {:error, reason} = Agent.run(request, user, skill: "knowledge")
    assert reason =~ "cost ceiling"

    assert Repo.reload!(request).status == :failed
  end

  test "a provider failure is recorded, with the question still on record", %{user: user} do
    FakeProvider.stop()

    {_conversation, request} = ask("a question", user)

    assert {:error, reason} = Agent.run(request, user, skill: "knowledge")

    # The adapter never passes provider detail outward, so the recorded reason is
    # the generic one; what actually failed is logged instead.
    assert reason == "The AI provider could not complete the request"

    request = Repo.reload!(request)
    assert request.status == :failed
    assert request.error == "The AI provider could not complete the request"

    assert [%Event{type: :user, content: "a question"}] =
             Event |> where([e], e.message_id == ^request.id) |> Repo.all()
  end

  test "a tool error is handed to the model rather than ending the run", %{user: user} do
    FakeProvider.script([
      FakeProvider.tool_use("get_flow", %{"flow_id" => 999_999}),
      FakeProvider.answer("There is no flow with that id.")
    ])

    {_conversation, request} = ask("describe flow 999999", user)

    assert {:ok, answer, _meta} = Agent.run(request, user, skill: "knowledge")
    assert answer =~ "no flow"

    result = Repo.one(from(e in Event, where: e.type == :tool_result, select: e.data))
    assert result["output"] =~ "No flow with id 999999"
    assert Repo.reload!(request).status == :succeeded
  end

  test "every tool the agent offers is one the gateway can run" do
    for spec <- Tools.all(), do: assert({:ok, {_module, ^spec}} = Tools.fetch(spec.name))
  end
end
