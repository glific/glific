defmodule GlificWeb.Resolvers.Guardrails do
  @moduledoc """
  Resolvers for the Kaapi guardrail validator catalog. Guardrails themselves live inline in the
  Kaapi config blob, so Glific only reads the catalog to build and check them.
  """

  alias Glific.ThirdParty.Kaapi

  @docs_url "https://projecttech4devai.github.io/kaapi-docs/guardrails"

  @validator_doc_links %{
    "gender_assumption_bias" => "#{@docs_url}/gender-neutrality",
    "pii_remover" => "#{@docs_url}/privacy-protection",
    "uli_slur_match" => "#{@docs_url}/content-safety",
    "topic_relevance_llm" => "#{@docs_url}/scope-control"
  }

  @doc """
  List the guardrail validator types Glific supports with their Kaapi config JSON schemas and doc links.
  """
  @spec list_guardrail_validators(map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def list_guardrail_validators(_, _, %{context: %{current_user: user}}) do
    case Kaapi.list_guardrail_validators(user.organization_id) do
      {:ok, %{validators: validators}} ->
        validators =
          for %{type: type} = validator <- validators,
              Map.has_key?(@validator_doc_links, type),
              do: Map.put(validator, :link, @validator_doc_links[type])

        {:ok, %{validators: validators}}

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
