defmodule GlificWeb.Resolvers.PromptGenerator do
  @moduledoc """
  Resolver for the PromptGenerator GraphQL surface.

  Thin web-layer boundary: validates/throttles, delegates to
  `Glific.PromptGenerator`, and shapes results.  All org context is derived
  from the authenticated `current_user` — never from client-supplied input.
  """

  alias Glific.PromptGenerator.PromptGenerationRequest
  alias Glific.Repo

  # Per-org rate limit for prompt generation requests.
  # Window: 60 seconds; max: 10 requests per org.
  @rate_limit_window_ms 60_000
  @rate_limit_max 10

  # Per-field character limit — consistent with the context-layer clamp.
  @max_field_length 2_000

  @doc """
  Initiates async prompt generation.

  Applies a per-org rate limit (10 req/60s) and per-field length cap
  (#{@max_field_length} chars) before delegating to `Glific.PromptGenerator.generate_prompt/3`.
  org_id and user_id are always sourced from `current_user`.
  """
  @spec generate(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def generate(_, %{input: params}, %{context: %{current_user: user}}) do
    rate_limit_key = "prompt_generation:#{user.organization_id}"

    with :ok <- check_rate(rate_limit_key),
         :ok <- validate_field_lengths(params),
         {:ok, request} <-
           Glific.PromptGenerator.generate_prompt(params, user.organization_id, user.id) do
      {:ok, %{prompt_generation: request}}
    end
  end

  @doc """
  Fetches a prompt generation request by id, scoped to the caller's org.

  A cross-org id returns `{:error, ["Resource not found"]}` from `Repo.fetch_by`,
  which surfaces as an error in the `:prompt_generation_result` wrapper — the same
  behavior as tag and other org-scoped by-id resolvers.
  """
  @spec get(Absinthe.Resolution.t(), %{id: integer()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def get(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, request} <-
           Repo.fetch_by(PromptGenerationRequest, %{
             id: id,
             organization_id: user.organization_id
           }) do
      {:ok, %{prompt_generation: request}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec check_rate(String.t()) :: :ok | {:error, String.t()}
  defp check_rate(key) do
    case ExRated.check_rate(key, @rate_limit_window_ms, @rate_limit_max) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, "Rate limit reached. Please try again in a minute."}
    end
  end

  @spec validate_field_lengths(map()) :: :ok | {:error, String.t()}
  defp validate_field_lengths(params) do
    oversized =
      params
      |> Enum.find(fn {_field, value} ->
        is_binary(value) && String.length(value) > @max_field_length
      end)

    case oversized do
      nil ->
        :ok

      {field, _value} ->
        {:error,
         "Field '#{field}' exceeds the maximum length of #{@max_field_length} characters."}
    end
  end
end
