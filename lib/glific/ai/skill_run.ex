defmodule Glific.AI.SkillRun do
  @moduledoc """
  Runs one skill on its own, for a caller that already knows which it wants.

  The other way in is `Glific.AI.AskGlific`, the chat window, which classifies
  intent and keeps a thread the person can come back to. This module is for a
  button: one request, a skill named outright, no classification and nothing to
  come back to.

  Both end up in `Glific.AI.Agent`, so a skill run gets the same tools, the
  same step, cost and duration ceilings and the same recording as a chat
  question. It is recorded against a thread of its own, marked `:skill_run`,
  which is what keeps it out of the chat history.
  """

  alias Glific.{
    AI.Agent,
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Skills,
    Repo,
    Users.User
  }

  @doc """
  Runs one skill against a question and returns its answer.

  The skill must be one `Glific.AI.Skills` knows; an unknown name is an error
  rather than a fallback, because a caller naming a skill has said what it
  wants.
  """
  @spec start(String.t(), String.t(), User.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def start(skill, query, %User{} = user, opts \\ []) do
    Repo.put_current_user(user)
    query = query |> to_string() |> String.trim()

    with :ok <- validate(skill, query),
         {:ok, skill_module} <- Skills.fetch(skill) do
      message = record_question(skill_module, user, query)

      case Agent.run(message, user, Keyword.put(opts, :skill, skill)) do
        {:ok, answer, meta} -> {:ok, result(answer, meta)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec validate(String.t() | nil, String.t()) :: :ok | {:error, String.t()}
  defp validate(skill, _query) when skill in [nil, ""], do: {:error, "Skill is required"}
  defp validate(_skill, ""), do: {:error, "Query is required"}
  defp validate(_skill, _query), do: :ok

  @spec record_question(module(), User.t(), String.t()) :: Message.t()
  defp record_question(skill, user, query) do
    conversation =
      %Conversation{}
      |> Conversation.changeset(%{
        user_id: user.id,
        organization_id: user.organization_id,
        kind: :skill_run,
        title: skill.name()
      })
      |> Repo.insert!()

    message =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        organization_id: conversation.organization_id,
        status: :running
      })
      |> Repo.insert!()

    %Event{}
    |> Event.changeset(%{
      message_id: message.id,
      conversation_id: message.conversation_id,
      organization_id: message.organization_id,
      step: 1,
      type: :user,
      content: query
    })
    |> Repo.insert!()

    message
  end

  @spec result(String.t(), Agent.meta()) :: map()
  defp result(answer, meta) do
    %{
      answer: answer,
      message_id: meta.answer_event_id && to_string(meta.answer_event_id),
      skill: meta.skill
    }
  end
end
