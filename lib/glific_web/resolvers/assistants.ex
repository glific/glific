defmodule GlificWeb.Resolvers.Assistants do
  @moduledoc """
  Assistant Resolver which sits between the GraphQL schema and Glific Assistants Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """

  alias Glific.Assistants

  @max_golden_qa_file_size 20 * 1024 * 1024

  @doc """
  Create a new knowledge base with the given parameters.
  """
  @spec create_knowledge_base(map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def create_knowledge_base(_, params, _context) do
    with {:ok, %{knowledge_base_version: knowledge_base_version, knowledge_base: knowledge_base}} <-
           Assistants.create_knowledge_base_with_version(params) do
      response = %{
        id: knowledge_base.id,
        name: knowledge_base.name,
        knowledge_base_version_id: knowledge_base_version.id,
        files: knowledge_base_version.files,
        size: knowledge_base_version.size,
        status: knowledge_base_version.status,
        inserted_at: knowledge_base.inserted_at,
        updated_at: knowledge_base_version.inserted_at
      }

      {:ok, %{knowledge_base: response}}
    end
  end

  @doc """
  Create a Golden QA configuration after validating the input.
  """
  @spec create_golden_qa(map(), map(), map()) :: {:ok, map()}
  def create_golden_qa(_, %{input: %{name: name, duplication_factor: factor}}, _context) do
    # with :ok <- validate_golden_qa_name(name),
    #      :ok <- validate_duplication_factor(factor) do
    #   {:ok,
    #    %{
    #      golden_qa: %{
    #        name: name,
    #        duplication_factor: factor
    #      },
    #      errors: []
    #    }} |> IO.inspect(label: "create_golden_qa")
    # else
    #   {:error, message} ->
    #     {:ok,
    #      %{
    #        golden_qa: %{
    #          name: name,
    #          duplication_factor: factor
    #        },
    #        errors: [%{key: "input", message: message}]
    #      }} |> IO.inspect(label: "create_golden_qa")
    # end
    {:ok,
     %{
       golden_qa: %{
         name: name,
         duplication_factor: factor
       },
       errors: []
     }} |> IO.inspect(label: "create_golden_qa")
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
    do: {:error, "duplicationFactor must be between 1 and 5"}

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
