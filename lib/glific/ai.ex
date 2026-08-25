defmodule Glific.AI do
  @moduledoc """
  Glific AI — the public boundary for asking a model something.

  At this stage this module does one thing: it decides whether Glific AI is
  permitted to run for an organisation, and if so hands the conversation to the
  configured provider. Routing, skills, tools and the agent loop sit above it in
  later work; storage lives in `Glific.AI.Conversation` and friends.

  Two guarantees callers can rely on:

    * with the feature flag off for an organisation, **no provider call is
      made** — the flag is checked before anything is sent
    * a provider failure comes back as `{:error, reason}`, never as an exception
  """

  alias Glific.{
    AI.Message,
    AI.Provider,
    AI.Usage,
    Flags,
    Partners
  }

  @doc """
  Whether Glific AI is enabled for this organisation.
  """
  @spec enabled?(non_neg_integer()) :: boolean()
  def enabled?(organization_id) do
    organization_id
    |> Partners.organization()
    |> Flags.get_glific_ai_enabled()
  end

  @doc """
  Sends a conversation to the configured provider on behalf of an organisation.

  Returns the model's reply and what the call consumed, so the caller can record
  cost against a request. Returns `{:error, :disabled}` without contacting any
  provider when the feature flag is off.
  """
  @spec generate(non_neg_integer(), [Message.t()], keyword()) ::
          {:ok, Message.t(), Usage.t()} | {:error, :disabled | Provider.failure()}
  def generate(organization_id, messages, opts \\ []) do
    if enabled?(organization_id) do
      Provider.impl().generate(messages, opts)
    else
      {:error, :disabled}
    end
  end
end
