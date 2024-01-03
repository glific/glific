defmodule Glific.Flows.Translate.Simple do
  @moduledoc """
  Code to translate using OpenAI as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message

  ## Examples

    iex> Glific.Flows.Translate.Simple.translate(["thankyou for joining", "correct answer"], "english", "hindi")
      {:ok, ["hindi thankyou for joining english", "hindi correct answer english"]}
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst) do
    result =
      strings
      |> Enum.map(fn s ->
        "#{dst} #{s} #{src}"
      end)

    {:ok, result}
  end
end
