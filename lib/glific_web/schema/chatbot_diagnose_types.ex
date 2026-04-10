defmodule GlificWeb.Schema.ChatbotDiagnoseTypes do
  @moduledoc """
  GraphQL types for the chatbotDiagnose query.
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  # --- Enums ---

  enum :diagnose_include_section do
    value(:contact_info, as: "CONTACT_INFO")
    value(:contact_fields, as: "CONTACT_FIELDS")
    value(:contact_history, as: "CONTACT_HISTORY")
    value(:messages, as: "MESSAGES")
    value(:flow_info, as: "FLOW_INFO")
    value(:flow_revisions, as: "FLOW_REVISIONS")
    value(:flow_contexts, as: "FLOW_CONTEXTS")
    value(:flow_results, as: "FLOW_RESULTS")
    value(:notifications, as: "NOTIFICATIONS")
    value(:triggers, as: "TRIGGERS")
    value(:oban_jobs, as: "OBAN_JOBS")
    value(:groups, as: "GROUPS")
    value(:contact_groups, as: "CONTACT_GROUPS")
    value(:tags, as: "TAGS")
    value(:templates, as: "TEMPLATES")
    value(:wa_messages, as: "WA_MESSAGES")
    value(:tickets, as: "TICKETS")
  end

  # --- Input types ---

  input_object :diagnose_contact_filter do
    field :id, :id
    field :phone, :string
    field :name, :string
  end

  input_object :diagnose_flow_filter do
    field :id, :id
    field :uuid, :string
    field :name, :string
  end

  input_object :chatbot_diagnose_input do
    field :contact, :diagnose_contact_filter
    field :flow, :diagnose_flow_filter
    field :time_range, :string
    field :include, list_of(:diagnose_include_section)
    field :limit, :integer
  end

  # --- Result object types ---

  object :diagnose_contact_info do
    field :id, :id
    field :name, :string
    field :phone, :string
    field :status, :string
    field :bsp_status, :string
    field :optin_status, :boolean
    field :optin_time, :datetime
    field :optout_time, :datetime
    field :optin_method, :string
    field :last_message_at, :datetime
    field :last_communication_at, :datetime
    field :fields, :json
    field :settings, :json
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_contact_history do
    field :id, :id
    field :event_type, :string
    field :event_label, :string
    field :event_meta, :json
    field :inserted_at, :datetime
  end

  object :diagnose_message do
    field :id, :id
    field :body, :string
    field :type, :string
    field :flow, :string
    field :status, :string
    field :bsp_status, :string
    field :errors, :json
    field :send_at, :datetime
    field :sent_at, :datetime
    field :message_number, :integer
    field :flow_id, :id
    field :sender_id, :id
    field :contact_id, :id
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_flow_info do
    field :id, :id
    field :name, :string
    field :uuid, :string
    field :keywords, list_of(:string)
    field :is_active, :boolean
    field :is_pinned, :boolean
    field :is_background, :boolean
    field :respond_other, :boolean
    field :ignore_keywords, :boolean
    field :version_number, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_flow_revision do
    field :id, :id
    field :flow_id, :id
    field :definition, :string
    field :status, :string
    field :version, :integer
    field :revision_number, :integer
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_flow_context do
    field :id, :id
    field :flow_id, :id
    field :flow_name, :string
    field :flow_uuid, :string
    field :contact_id, :id
    field :contact_name, :string
    field :contact_phone, :string
    field :status, :string
    field :node_uuid, :string
    field :parent_id, :id
    field :results, :json
    field :is_killed, :boolean
    field :is_background_flow, :boolean
    field :is_await_result, :boolean
    field :wakeup_at, :datetime
    field :completed_at, :datetime
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_flow_result do
    field :id, :id
    field :flow_id, :id
    field :flow_name, :string
    field :contact_id, :id
    field :contact_name, :string
    field :results, :json
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_notification do
    field :id, :id
    field :category, :string
    field :message, :string
    field :severity, :string
    field :entity, :json
    field :is_read, :boolean
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_trigger do
    field :id, :id
    field :name, :string
    field :flow_id, :id
    field :flow_name, :string
    field :start_at, :datetime
    field :end_date, :date
    field :is_active, :boolean
    field :is_repeating, :boolean
    field :frequency, list_of(:string)
    field :days, list_of(:integer)
    field :inserted_at, :datetime
  end

  object :diagnose_oban_job do
    field :id, :id
    field :state, :string
    field :queue, :string
    field :worker, :string
    field :args, :json
    field :errors, :json
    field :attempt, :integer
    field :max_attempts, :integer
    field :inserted_at, :datetime
    field :scheduled_at, :datetime
    field :completed_at, :datetime
  end

  object :diagnose_group do
    field :id, :id
    field :label, :string
    field :description, :string
    field :is_restricted, :boolean
    field :inserted_at, :datetime
  end

  object :diagnose_contact_group do
    field :group_id, :id
    field :group_label, :string
    field :inserted_at, :datetime
  end

  object :diagnose_tag do
    field :id, :id
    field :label, :string
    field :description, :string
    field :inserted_at, :datetime
  end

  object :diagnose_template do
    field :id, :id
    field :label, :string
    field :body, :string
    field :type, :string
    field :shortcode, :string
    field :status, :string
    field :is_hsm, :boolean
    field :is_active, :boolean
    field :number_parameters, :integer
    field :category, :string
    field :inserted_at, :datetime
  end

  object :diagnose_wa_message do
    field :id, :id
    field :body, :string
    field :type, :string
    field :status, :string
    field :bsp_status, :string
    field :contact_id, :id
    field :flow, :string
    field :inserted_at, :datetime
  end

  object :diagnose_ticket do
    field :id, :id
    field :body, :string
    field :topic, :string
    field :status, :string
    field :remarks, :string
    field :contact_id, :id
    field :user_id, :id
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :diagnose_diagnostics do
    field :contact_opted_in, :boolean
    field :contact_session_active, :boolean
    field :contact_in_active_flow, :boolean
    field :flow_is_published, :boolean
    field :flow_is_active, :boolean
    field :recent_error_count, :integer
    field :pending_oban_jobs, :integer
  end

  # --- Main result type ---

  object :chatbot_diagnose_result do
    field :contact_info, :diagnose_contact_info
    field :contact_history, list_of(:diagnose_contact_history)
    field :messages, list_of(:diagnose_message)
    field :flow_info, :diagnose_flow_info
    field :flow_revisions, list_of(:diagnose_flow_revision)
    field :flow_contexts, list_of(:diagnose_flow_context)
    field :flow_results, list_of(:diagnose_flow_result)
    field :notifications, list_of(:diagnose_notification)
    field :triggers, list_of(:diagnose_trigger)
    field :oban_jobs, list_of(:diagnose_oban_job)
    field :groups, list_of(:diagnose_group)
    field :contact_groups, list_of(:diagnose_contact_group)
    field :tags, list_of(:diagnose_tag)
    field :templates, list_of(:diagnose_template)
    field :wa_messages, list_of(:diagnose_wa_message)
    field :tickets, list_of(:diagnose_ticket)
    field :diagnostics, :diagnose_diagnostics
  end

  # --- Query ---

  object :chatbot_diagnose_queries do
    @desc "Diagnostic query for AI chatbot — fetches data across multiple tables in one call"
    field :chatbot_diagnose, :chatbot_diagnose_result do
      arg(:input, non_null(:chatbot_diagnose_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ChatbotDiagnose.chatbot_diagnose/3)
    end
  end
end
