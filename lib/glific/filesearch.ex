defmodule Glific.Filesearch do
  @moduledoc """
  Main module to interact with filesearch
  """

  alias Glific.OpenAI.Filesearch.ApiClient

  @default_model "gpt-4o"
  @excluded_models_prefix ["dall", "tts", "babbage", "whisper", "text", "davinci"]

  @doc """
  Fetch available openai models
  """
  @spec list_models :: list(String.t())
  def list_models do
    case ApiClient.list_models() do
      {:ok, %{data: models}} ->
        models
        |> Stream.filter(fn model -> model.owned_by not in ["project-tech4dev"] end)
        |> Stream.filter(fn model ->
          not String.starts_with?(model.id, @excluded_models_prefix)
        end)
        |> Enum.map(fn model -> model.id end)

      _ ->
        [@default_model]
    end
  end
end
