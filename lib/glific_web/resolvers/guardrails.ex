defmodule GlificWeb.Resolvers.Guardrails do
  @moduledoc """
  Resolvers for the Kaapi guardrail validator catalog. Guardrails themselves live inline in the
  Kaapi config blob, so Glific only reads the catalog to build and check them.
  """

  alias Glific.ThirdParty.Kaapi

  @supported_validator_types [
    "gender_assumption_bias",
    "uli_slur_match",
    "pii_remover",
    "profanity_free",
    "topic_relevance_llm"
  ]

  @doc """
  List the guardrail validator types Glific supports along with their Kaapi config JSON schemas.
  """
  @spec list_guardrail_validators(map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def list_guardrail_validators(_, _, %{context: %{current_user: user}}) do
    case Kaapi.list_guardrail_validators(user.organization_id) do
      {:ok, %{validators: validators}} ->
        {:ok, %{validators: Enum.filter(validators, &(&1.type in @supported_validator_types))}}

      {:error, :timeout} ->
        {:error, "Timeout occurred, please try again."}

      {:error, %{status: _, body: %{error: error}}} ->
        {:error, error}

      {:error, message} when is_binary(message) ->
        {:error, message}

      _ ->
        {:error, "An unknown error occurred, please contact Glific support."}
    end
  end
end
