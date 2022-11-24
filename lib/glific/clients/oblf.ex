defmodule Glific.Clients.Oblf do
  @moduledoc """
  Custom webhook implementation specific to OBLF use case
  """

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("get_question_buttons", fields) do

    buttons =
      fields["daily_question"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields) do
    %{
      response: String.equivalent?(fields["correct_response"], fields["user_response"])
    }
  end

  def webhook(_, _fields),
    do: %{}
end
