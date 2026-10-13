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

  @unknown_error "An unknown error occurred, please contact Glific support."

  @doc """
  List the guardrail validator types Glific supports along with their Kaapi config JSON schemas.
  """
  @spec list_guardrail_validators(map(), map(), map()) :: {:ok, map()}
  def list_guardrail_validators(_, _, %{context: %{current_user: user}}) do
    case Kaapi.list_guardrail_validators(user.organization_id) do
      {:ok, %{validators: validators}} ->
        {:ok, %{validators: Enum.filter(validators, &(&1.type in @supported_validator_types))}}

      {:ok, %{error: error}} when is_binary(error) ->
        errors(error)

      {:ok, _} ->
        errors(@unknown_error)

      {:error, reason} ->
        errors(error_message(reason))
    end
  end

  @spec error_message(any()) :: String.t()
  defp error_message(:timeout), do: "Timeout occurred, please try again."
  defp error_message(%{body: %{error: error}}) when is_binary(error), do: error
  defp error_message(%{body: %{detail: detail}}) when is_binary(detail), do: detail
  defp error_message(message) when is_binary(message), do: message
  defp error_message(_), do: @unknown_error

  @spec errors(String.t()) :: {:ok, map()}
  defp errors(message), do: {:ok, %{errors: [%{message: message}]}}
end
