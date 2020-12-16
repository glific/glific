defmodule Glific.Clients.Stir do
  @moduledoc """
  Example implementation of survey computation for STiR
  """

  @doc false
  @spec webhook(map) :: map()
  def webhook(%{results: results}),
    do: compute_survey_score(results)

  def webhook(_), do: %{}

  defp get_value(k, v) do
    k = String.downcase(k)
    input = String.downcase(v["input"])

    if input == "y" do
      case k do
        "a1" -> 1
        "a2" -> 2
        "a3" -> 4
        "a4" -> 8
        "a5" -> 16
        _ -> 0
      end
    else
      0
    end
  end

  @doc """
  Return integer depending on number of n as response in messages
  """
  @spec compute_art_results(map()) :: non_neg_integer()
  def compute_art_results(results) do
    answers =
      results
      |> Enum.map(fn {_k, v} -> String.downcase(v["input"]) end)
      |> Enum.reduce(%{}, fn x, acc -> Map.update(acc, x, 1, &(&1 + 1)) end)

    cond do
      is_nil(Map.get(answers, "n")) -> 3
      Map.get(answers, "n") == 1 -> 1
      Map.get(answers, "n") > 1 -> 2
      true -> 3
    end
  end

  @doc """
  Return total score
  """
  @spec compute_survey_score(map()) :: map()
  def compute_survey_score(results) do
    results
    |> Enum.reduce(
      0,
      fn {k, v}, acc -> acc + get_value(k, v) end
    )
    |> get_content()
  end

  defp get_content(score) do
    {status, content} =
      cond do
        rem(score, 7) == 0 -> {1, "Your score: #{score} is divisible by 7"}
        rem(score, 5) == 0 -> {2, "Your score: #{score} is divisible by 5"}
        rem(score, 3) == 0 -> {3, "Your score: #{score} is divisible by 3"}
        rem(score, 2) == 0 -> {4, "Your score: #{score} is divisible by 2"}
        true -> {5, "Your score: #{score} is not divisible by 2, 3, 5 or 7"}
      end

    %{
      status: to_string(status),
      content: content,
      score: to_string(score)
    }
  end
end
