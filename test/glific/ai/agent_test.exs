defmodule Glific.AI.AgentTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    AI.Agent,
    AI.ChatMessage,
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Tools,
    AI.Usage,
    Fixtures,
    Repo
  }

  # Each provider is a script: a list of replies handed out in order, so a test
  # can stage "call a tool, then answer" without touching a real provider.
  defmodule ScriptedProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    def script(replies), do: Process.put(:script, replies)

    @impl Glific.AI.Provider
    def generate(messages, _opts) do
      Process.put(:seen, Process.get(:seen, []) ++ [messages])

      case Process.get(:script, []) do
        [reply | rest] ->
          Process.put(:script, rest)
          {:ok, reply, %Usage{input_tokens: 10, output_tokens: 5, cost: Decimal.new("0.001")}}

        [] ->
          {:ok, ChatMessage.assistant("done"), %Usage{cost: Decimal.new("0.001")}}
      end
    end
  end

  defmodule LoopingProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(_messages, _opts) do
      call = %{id: Ecto.UUID.generate(), name: "list_flows", args: %{}}
      {:ok, ChatMessage.assistant(nil, [call]), %Usage{cost: Decimal.new("0.001")}}
    end
  end

  defmodule ExpensiveProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(_messages, _opts) do
      call = %{id: Ecto.UUID.generate(), name: "list_flows", args: %{}}
      {:ok, ChatMessage.assistant(nil, [call]), %Usage{cost: Decimal.new("10.00")}}
    end
  end

  defmodule FailingProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(_messages, _opts), do: {:error, {:provider_error, "upstream is down"}}
  end

  defp use_provider(provider) do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.put(original, :provider, provider))
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)
  end

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
    Fixtures.flow_fixture(%{organization_id: 1, name: "Registration flow"})
    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  test "the model can read data before answering, and every step is recorded", %{user: user} do
    use_provider(ScriptedProvider)

    ScriptedProvider.script([
      ChatMessage.assistant(nil, [%{id: "call_1", name: "list_flows", args: %{"name" => "Reg"}}]),
      ChatMessage.assistant("You have one flow called Registration flow.")
    ])

    {_conversation, request} = ask("what flows do I have?", user)

    assert {:ok, answer} = Agent.run(request, user)
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

  test "cost and outcome are recorded on the request", %{user: user} do
    use_provider(ScriptedProvider)
    ScriptedProvider.script([ChatMessage.assistant("a short answer")])

    {_conversation, request} = ask("hello", user)
    assert {:ok, _} = Agent.run(request, user)

    request = Repo.reload!(request)
    assert request.status == :succeeded
    assert request.input_tokens == 10
    assert Decimal.equal?(request.cost, Decimal.new("0.001"))
    assert request.model
  end

  test "a follow-up carries the earlier exchange", %{user: user} do
    use_provider(ScriptedProvider)
    ScriptedProvider.script([ChatMessage.assistant("An HSM is a template message.")])

    {conversation, first} = ask("what is an HSM?", user)
    assert {:ok, _} = Agent.run(first, user)

    Process.delete(:seen)
    ScriptedProvider.script([ChatMessage.assistant("You send one from a flow.")])
    {_, second} = ask("how do I send one?", user, conversation)
    assert {:ok, _} = Agent.run(second, user)

    [sent | _] = Process.get(:seen)

    assert Enum.map(sent, & &1.role) == [:system, :user, :assistant, :user]

    assert Enum.map(sent, & &1.content) == [
             hd(sent).content,
             "what is an HSM?",
             "An HSM is a template message.",
             "how do I send one?"
           ]
  end

  test "a model that keeps calling tools is stopped by the step limit", %{user: user} do
    use_provider(LoopingProvider)
    set_limits(max_steps: 6)

    {_conversation, request} = ask("loop forever", user)

    assert {:error, reason} = Agent.run(request, user)
    assert reason =~ "limit of 6 steps"

    request = Repo.reload!(request)
    assert request.status == :failed
    assert request.error =~ "6 steps"

    steps = Event |> where([e], e.message_id == ^request.id) |> Repo.aggregate(:count)
    assert steps >= 6
  end

  test "a run is stopped by the cost ceiling", %{user: user} do
    use_provider(ExpensiveProvider)
    set_limits(max_cost_usd: "0.50", max_steps: 50)

    {_conversation, request} = ask("expensive question", user)

    assert {:error, reason} = Agent.run(request, user)
    assert reason =~ "cost ceiling"

    assert Repo.reload!(request).status == :failed
  end

  test "a provider failure is recorded, with the question still on record", %{user: user} do
    use_provider(FailingProvider)

    {_conversation, request} = ask("a question", user)

    assert {:error, "upstream is down"} = Agent.run(request, user)

    request = Repo.reload!(request)
    assert request.status == :failed
    assert request.error == "upstream is down"

    assert [%Event{type: :user, content: "a question"}] =
             Event |> where([e], e.message_id == ^request.id) |> Repo.all()
  end

  test "a tool error is handed to the model rather than ending the run", %{user: user} do
    use_provider(ScriptedProvider)

    ScriptedProvider.script([
      ChatMessage.assistant(nil, [
        %{id: "call_1", name: "get_flow", args: %{"flow_id" => 999_999}}
      ]),
      ChatMessage.assistant("There is no flow with that id.")
    ])

    {_conversation, request} = ask("describe flow 999999", user)

    assert {:ok, answer} = Agent.run(request, user)
    assert answer =~ "no flow"

    result = Repo.one(from(e in Event, where: e.type == :tool_result, select: e.data))
    assert result["output"] =~ "No flow with id 999999"
    assert Repo.reload!(request).status == :succeeded
  end

  test "every tool the agent offers is one the gateway can run" do
    for tool <- Tools.all(), do: assert({:ok, ^tool} = Tools.fetch(tool.name()))
  end
end
