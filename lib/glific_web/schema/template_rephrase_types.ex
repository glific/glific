defmodule GlificWeb.Schema.TemplateRephraseTypes do
  @moduledoc """
  GraphQL type definitions for the TemplateRephrase domain.

  Exposes a single mutation to initiate async WhatsApp template body rephrasing and
  a query to poll the resulting `TemplateRephraseRequest` row by id.
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.{Authorize, RequireFeatureFlag}

  enum :template_rephrase_action do
    value(:professional)
    value(:utility)
    value(:custom)
  end

  object :template_rephrase_result do
    field(:template_rephrase, :template_rephrase)
    field(:errors, list_of(:input_error))
  end

  object :template_rephrase do
    field(:id, :id)
    field(:status, :string)
    field(:rephrased_text, :string)
    field(:error_message, :string)
    field(:original_text, :string)
    field(:action, :string)
  end

  @desc "Input object for template rephrasing. `custom_prompt` is required only when
  `action` is CUSTOM; this is validated in the resolver, not the schema."
  input_object :template_rephrase_input do
    @desc "The WhatsApp template body text to rephrase"
    field(:text, non_null(:string))

    @desc "The rephrase action to apply"
    field(:action, non_null(:template_rephrase_action))

    @desc "Free-text rephrase instruction; required only when action is CUSTOM"
    field(:custom_prompt, :string)
  end

  object :template_rephrase_queries do
    @desc "Fetch the status and result of a template rephrase request by id"
    field :template_rephrase, :template_rephrase_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.TemplateRephrase.get/3)
    end
  end

  object :template_rephrase_mutations do
    @desc "Initiate async rephrasing of a WhatsApp template body via Kaapi"
    field :rephrase_template_body, :template_rephrase_result do
      arg(:input, non_null(:template_rephrase_input))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_template_ai_assist_enabled, "AI Assist for Templates"})
      resolve(&Resolvers.TemplateRephrase.generate/3)
    end
  end
end
