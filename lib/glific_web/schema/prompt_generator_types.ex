defmodule GlificWeb.Schema.PromptGeneratorTypes do
  @moduledoc """
  GraphQL type definitions for the PromptGenerator domain.

  Exposes a single mutation to initiate async system-prompt generation and
  a query to poll the resulting `PromptGenerationRequest` row by id.
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :prompt_generation_result do
    field(:prompt_generation, :prompt_generation)
    field(:errors, list_of(:input_error))
  end

  object :prompt_generation do
    field(:id, :id)
    field(:status, :string)
    field(:generated_prompt, :string)
    field(:error_message, :string)

    @desc "The submitted answers as a flexible JSON map (for pre-filling the wizard). Kept
    as :json rather than a typed object so adding/removing questions only touches the
    frontend + the generation meta-prompt, not this schema."
    field(:inputs, :json)
  end

  @desc "Input object for prompt generation — the 9-question NGO answers"
  input_object :prompt_generator_input do
    @desc "Organization or chatbot name"
    field(:name, :string)

    @desc "Purpose or mission of the chatbot"
    field(:purpose, :string)

    @desc "Target audience"
    field(:audience, :string)

    @desc "Language policy (e.g. Hindi and English)"
    field(:language, :string)

    @desc "Desired tone (e.g. friendly, professional)"
    field(:tone, :string)

    @desc "Response format guidelines"
    field(:format, :string)

    @desc "Off-limits topics the chatbot must avoid"
    field(:off_limits, :string)

    @desc "Exact fallback message when the chatbot cannot answer"
    field(:fallback, :string)

    @desc "Escalation path (e.g. how to reach a human agent)"
    field(:escalation, :string)
  end

  object :prompt_generator_queries do
    @desc "Fetch the status and result of a prompt generation request by id"
    field :prompt_generation, :prompt_generation_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.PromptGenerator.get/3)
    end

    @desc "Fetch the current user's most recent prompt generation request (for pre-filling the wizard)"
    field :latest_prompt_generation, :prompt_generation_result do
      middleware(Authorize, :staff)
      resolve(&Resolvers.PromptGenerator.get_latest/3)
    end
  end

  object :prompt_generator_mutations do
    @desc "Initiate async generation of a WhatsApp chatbot system prompt via Kaapi"
    field :generate_prompt, :prompt_generation_result do
      arg(:input, non_null(:prompt_generator_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.PromptGenerator.generate/3)
    end
  end
end
