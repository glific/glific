defmodule Glific.AI do
  @moduledoc """
  Entry point for asking a model something.

  Checks whether Glific AI is enabled for the organisation, then hands the
  conversation to the configured provider.

  With the flag off, no provider call is made. A provider failure is returned as
  `{:error, reason}` rather than raised.
  """

  alias Glific.{
    AI.ChatMessage,
    AI.Provider,
    Flags,
    Partners
  }

  @doc """
  Whether Glific AI is enabled for this organisation.
  """
  @spec enabled?(non_neg_integer()) :: boolean()
  def enabled?(organization_id) do
    Flags.get_flag_enabled(:glific_ai_enabled, Partners.organization(organization_id))
  end

  @doc """
  Sends a conversation to the provider on behalf of an organisation.

  Returns the model's reply and what the call consumed, so the caller can record
  the cost.

  Returns `{:error, :disabled}` without contacting any provider when the feature
  flag is off.
  """
  @spec generate(non_neg_integer(), [ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Provider.usage()} | {:error, :disabled | Provider.failure()}
  def generate(organization_id, messages, opts \\ []) do
    if enabled?(organization_id) do
      Provider.impl().generate(messages, opts)
    else
      {:error, :disabled}
    end
  end
end
