defmodule GlificWeb.Resolvers.TemplateRephrase do
  @moduledoc """
  Resolver for the TemplateRephrase GraphQL surface.

  Thin web-layer boundary: validates/throttles, delegates to
  `Glific.TemplateRephrase`, and shapes results. All org context is derived
  from the authenticated `current_user` — never from client-supplied input.
  """

  alias Glific.Repo
  alias Glific.TemplateRephrase.TemplateRephraseRequest

  # Per-org rate limit for template rephrase requests. Tighter than PromptGenerator's
  # 10/60s since this is a per-click action rather than a one-time wizard submission.
  # Window: 60 seconds; max: 20 requests per org.
  @rate_limit_window_ms 60_000
  @rate_limit_max 20

  # WhatsApp HSM template body limit.
  @max_text_length 1_024

  # Max length for the free-text custom rephrase instruction.
  @max_custom_prompt_length 300

  @doc """
  Initiates async template body rephrasing.

  Applies a per-org rate limit (20 req/60s), a template body length cap
  (#{@max_text_length} chars), and — for the CUSTOM action — a required, non-blank
  `custom_prompt` capped at #{@max_custom_prompt_length} chars, before delegating to
  `Glific.TemplateRephrase.rephrase/3`. org_id and user_id are always sourced from
  `current_user`.
  """
  @spec generate(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def generate(_, %{input: params}, %{context: %{current_user: user}}) do
    rate_limit_key = "template_rephrase:#{user.organization_id}"

    with :ok <- check_rate(rate_limit_key),
         :ok <- validate_text(params[:text]),
         :ok <- validate_custom_prompt(params[:action], params[:custom_prompt]),
         {:ok, request} <-
           Glific.TemplateRephrase.rephrase(
             %{
               text: params[:text],
               action: params[:action],
               custom_prompt: params[:custom_prompt]
             },
             user.organization_id,
             user.id
           ) do
      {:ok, %{template_rephrase: request}}
    end
  end

  @doc """
  Fetches a template rephrase request by id, scoped to the caller's org.

  A cross-org id returns `{:error, ["Resource not found"]}` from `Repo.fetch_by`,
  which surfaces as an error in the `:template_rephrase_result` wrapper — the same
  behavior as tag and other org-scoped by-id resolvers.
  """
  @spec get(Absinthe.Resolution.t(), %{id: integer()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def get(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, request} <-
           Repo.fetch_by(TemplateRephraseRequest, %{
             id: id,
             organization_id: user.organization_id
           }) do
      {:ok, %{template_rephrase: request}}
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

  @spec validate_text(String.t() | nil) :: :ok | {:error, String.t()}
  defp validate_text(text) when is_binary(text) do
    cond do
      String.trim(text) == "" ->
        {:error, "Template body text cannot be blank."}

      String.length(text) > @max_text_length ->
        {:error,
         "Template body text exceeds the maximum length of #{@max_text_length} characters."}

      true ->
        :ok
    end
  end

  defp validate_text(_text), do: {:error, "Template body text cannot be blank."}

  @spec validate_custom_prompt(atom(), String.t() | nil) :: :ok | {:error, String.t()}
  defp validate_custom_prompt(:custom, custom_prompt) when is_binary(custom_prompt) do
    cond do
      String.trim(custom_prompt) == "" ->
        {:error, "A custom instruction is required when action is CUSTOM."}

      String.length(custom_prompt) > @max_custom_prompt_length ->
        {:error,
         "Custom instruction exceeds the maximum length of #{@max_custom_prompt_length} characters."}

      true ->
        :ok
    end
  end

  defp validate_custom_prompt(:custom, _custom_prompt),
    do: {:error, "A custom instruction is required when action is CUSTOM."}

  defp validate_custom_prompt(_action, _custom_prompt), do: :ok
end
