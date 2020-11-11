defmodule GlificWeb.Flows.WebhookController do
  @moduledoc """
  Experimental approach on trying to handle webhooks for NGOs within the system.
  This bypasses using a third party and hence makes things a lot more efficient
  """

  use GlificWeb, :controller

  @doc """
  Example implementation of survey computation for STiR
  """
  @spec stir_survey(Plug.Conn.t(), map) :: Plug.Conn.t()
  def stir_survey(conn, %{"results" => results} = _params) do
    json = compute_survey_score(results)

    conn
    |> json(%{results: json})
  end

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

  defp compute_survey_score(results) do
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
