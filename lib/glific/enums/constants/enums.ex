defmodule Glific.Enums.Constants do
  @moduledoc """
  The Enums constant are where all enum values across our entire
  application should be defined. This is the source of truth for
  all enums
  """

  defmacro __using__(_opts) do
    quote do
      # standard first part of a tuple for many api calls
      @api_status_const [:ok, :error]

      # the status determines if we can send a message to the contact
      @contact_status_const [:blocked, :failed, :invalid, :processing, :valid]

      # the provider status determines if we can send a message to the contact
      @contact_provider_status_const [:none, :session, :session_and_hsm, :hsm]

      # the enums for the flow engine
      @flow_case_const [:has_any_word]

      @flow_router_const [:switch]

      @flow_action_type_const [
        :enter_flow,
        :send_msg,
        :set_contact_language,
        :wait_for_response,
        :set_contact_field
      ]

      @flow_type_const [:message]

      # the direction of the messages: inbound: provider to glific, outbound: glific to provider
      @message_flow_const [:inbound, :outbound]

      # the status of the message as indicated by the provider
      @message_status_const [
        :sent,
        :delivered,
        :enqueued,
        :error,
        :read,
        :received,
        :contact_opt_out,
        :reached,
        :seen,
        :played,
        :deleted
      ]

      # the different possible types of message
      @message_type_const [
        :audio,
        :contact,
        :document,
        :hsm,
        :image,
        :location,
        :list,
        :quick_reply,
        :text,
        :video,
        :sticker,
        :location_request_message,
        :poll,
        :whatsapp_form_response
      ]

      # the different possible types of interactive message
      @interactive_message_type_const [:list, :quick_reply, :location_request_message]

      # the different possible types of import contact types
      @import_contacts_type_const [:file_path, :url, :data]

      # the possible question type constants
      @question_type_const [:text, :numeric, :date]

      # the possible sort direction for lists/rows, typically used in DB operations
      @sort_order_const [:asc, :desc]

      # Supported types for contact field values
      @contact_field_value_type_const [:text, :integer, :number, :boolean, :date]

      # Contact fields scope types
      @contact_field_scope_const [:contact, :globals, :wa_group]

      # User roles
      @user_roles_const [:none, :staff, :manager, :admin, :glific_admin]

      # Template button types
      @template_button_type_const [:call_to_action, :quick_reply, :otp, :whatsapp_form]

      # organization status types
      @organization_status_const [
        # when organization is there but not active
        :inactive,
        # Admin approves the organization and it's ready to setup.
        :approved,
        # Organization is fully functional and activated
        :active,
        # organization is suspended and no activity can be performed on that
        :suspended,
        # admin wants to delete the organization
        :ready_to_delete,
        # force suspend accounts in case of payment defaulting
        :forced_suspension
      ]

      # types of template we can use for custom certificates
      @certificate_template_type_const [
        :slides
      ]

      # Sheet sync status types
      @sheet_sync_status_const [
        :success,
        :failed
      ]

      # status of whatsapp form
      @whatsapp_form_status_const [
        :draft,
        :published,
        :inactive
      ]

      @whatsapp_form_category_const [
        :sign_up,
        :sign_in,
        :appointment_booking,
        :lead_generation,
        :contact_us,
        :customer_support,
        :survey,
        :other
      ]
    end
  end
end
