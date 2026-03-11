defmodule GlificWeb.Resolvers.AIEvaluations do
  @moduledoc """
  Resolvers for AI Evaluations
  """

  alias Glific.ThirdParty.Kaapi

  # 20MB
  @max_golden_qa_file_size 20 * 1024 * 1024

  @doc """
  Create a Golden QA configuration after validating the input.
  """
  @spec create_golden_qa(map(), map(), map()) :: {:ok, map()}
  def create_golden_qa(_, %{input: %{name: name, file: file, duplication_factor: factor}}, %{
        context: %{current_user: user}
      }) do
    result =
      with :ok <- validate_golden_qa_name(name),
           :ok <- validate_duplication_factor(factor),
           :ok <- validate_golden_qa_file_size(file) do
        Kaapi.upload_evaluation_dataset(
          %{dataset_name: name, file: file, duplication_factor: factor},
          user.organization_id
        )
    end

    case result do
      {:ok, res} -> {:ok, %{golden_qa: res}}
      {:error, :timeout} -> {:ok, %{errors: [%{message: "Timeout occurred, please try again."}]}}
      {:error, %{status: _, body: %{:error => error}}} -> {:ok, %{errors: [%{message: error}]}}
      {:error, msg} when is_binary(msg) -> {:ok, %{errors: [%{message: msg}]}}
      {:error, _err} -> {:ok, %{errors: [%{message: "An unknown error occurred, please contact Glific support."}]}}
    end
  end

  @spec validate_golden_qa_name(String.t()) :: :ok | {:error, String.t()}
  defp validate_golden_qa_name(name) do
    if Regex.match?(~r/^[A-Za-z0-9_]+$/, name) do
      :ok
    else
      {:error, "Name can only contain alphanumeric characters and underscores"}
    end
  end

  @spec validate_duplication_factor(integer()) :: :ok | {:error, String.t()}
  defp validate_duplication_factor(factor) when factor in 1..5, do: :ok

  defp validate_duplication_factor(_factor),
    do: {:error, "Duplication factor must be between 1 and 5"}

  @spec validate_golden_qa_file_size(struct()) :: :ok | {:error, String.t()}
  defp validate_golden_qa_file_size(%{path: path}) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_golden_qa_file_size ->
        :ok

      {:ok, %{size: _size}} ->
        {:error, "File size must not exceed 20MB"}

      {:error, _reason} ->
        {:error, "Unable to read uploaded file for size validation"}
    end
  end
end
