defmodule Glific.AI.Router do
  @moduledoc """
  Decides which skill should handle a request.

  One cheap provider call: the question plus the skill catalogue, no tools, a
  16-token ceiling and the model named by `:classifier_model`, so classifying
  costs a fraction of answering. If the call fails or the model
  names something unknown, the default skill handles it — a misrouted answer is
  better than no answer, and the default only reads.

  With a single skill there is nothing to decide, so no call is made at all.

  Skipped entirely when the caller already knows the skill, which is how a
  "Draft HSM" button avoids paying for classification at all.
  """

  alias Glific.AI
  alias Glific.AI.{ChatMessage, Provider, Skills}

  @doc """
  The skill that should handle this question.

  Returns the skill module, what the classification consumed so the caller can
  add it to the run's cost, and whether a model chose it. No model chooses when
  only one skill is registered, or when the call fails and the default is
  used.
  """
  @spec classify(non_neg_integer(), String.t(), keyword()) ::
          {module(), Provider.usage(), boolean()}
  def classify(organization_id, question, opts \\ []) do
    case Skills.all() do
      [only] -> {only, zero_usage(), false}
      skills -> ask(organization_id, question, skills, opts)
    end
  end

  @spec ask(non_neg_integer(), String.t(), [module()], keyword()) ::
          {module(), Provider.usage(), boolean()}
  defp ask(organization_id, question, skills, opts) do
    case AI.generate(organization_id, messages(question, skills), request_opts(opts)) do
      {:ok, %ChatMessage{content: content}, usage} ->
        {resolve(content), usage, true}

      {:error, _reason} ->
        {Skills.default(), zero_usage(), false}
    end
  end

  # Only what the provider understands: the caller's opts carry agent concerns
  # such as `:skill`, and req_llm rejects an option it does not know.
  @spec request_opts(keyword()) :: keyword()
  defp request_opts(opts) do
    opts
    |> Keyword.take([:base_url, :api_key])
    |> Keyword.put(:model, classifier_model())
    |> Keyword.put(:max_tokens, 16)
  end

  # `:classifier_model` is separate from the model that answers questions, so
  # upgrading that one does not change what classifying costs.
  @spec classifier_model() :: String.t() | nil
  defp classifier_model do
    config = Application.get_env(:glific, Glific.AI, [])
    config[:classifier_model] || config[:model]
  end

  @spec resolve(String.t() | nil) :: module()
  defp resolve(content) do
    name = content |> to_string() |> String.trim() |> String.downcase()

    case Skills.fetch(name) do
      {:ok, skill} -> skill
      {:error, _} -> Skills.default()
    end
  end

  @spec messages(String.t(), [module()]) :: [ChatMessage.t()]
  defp messages(question, skills) do
    [
      ChatMessage.system("""
      Decide which skill should handle the request. Reply with the skill's name
      and nothing else — no punctuation, no explanation.

      #{catalogue(skills)}

      If none clearly fits, reply #{Skills.default().name()}.
      """),
      ChatMessage.user(question)
    ]
  end

  @spec catalogue([module()]) :: String.t()
  defp catalogue(skills) do
    Enum.map_join(skills, "\n\n", fn skill ->
      "#{skill.name()}: #{String.trim(skill.description())}"
    end)
  end

  @spec zero_usage() :: Provider.usage()
  defp zero_usage, do: %{input_tokens: 0, output_tokens: 0, cost: 0}
end
