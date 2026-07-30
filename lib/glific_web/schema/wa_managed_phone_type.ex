defmodule GlificWeb.Schema.WAManagedPhoneTypes do
  @moduledoc """
  GraphQL Representation of Glific's WAManagedPhone DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :wa_managed_phone_result do
    field :wa_managed_phone, :wa_managed_phone
    field :errors, list_of(:input_error)
  end

  object :wa_managed_phone do
    field :id, :id
    field :phone, :string
    field :phone_id, :integer
    field :label, :string
    field :status, :string
    field :last_status_checked_at, :datetime
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :contact, :contact do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  @desc "The QR / login screen for a managed phone, used to reconnect it from Glific"
  object :wa_phone_screen do
    @desc "The QR payload to render — a data-url / base64 image or Maytapi screen string"
    field :code, :string

    @desc "The phone's current Maytapi status at fetch time (e.g. qr-screen, active)"
    field :status, :string

    @desc "Hint for when the frontend should refresh the QR (Maytapi rotates it)"
    field :expires_at, :datetime
  end

  object :wa_phone_screen_result do
    field :wa_phone_screen, :wa_phone_screen
    field :errors, list_of(:input_error)
  end

  object :wa_phone_status_sync_result do
    field :message, :string
    field :errors, list_of(:input_error)
  end

  @desc "Filtering options for wa_managed_phones"
  input_object :wa_managed_phone_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the phone"
    field :phone, :string
  end

  object :wa_managed_phone_queries do
    @desc "Get a list of all wa_managed_phones filtered by various criteria"
    field :wa_managed_phones, list_of(:wa_managed_phone) do
      arg(:filter, :wa_managed_phone_filter)
      arg(:opts, :opts)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WAManagedPhones.wa_managed_phones/3)
    end

    @desc "Get a count of all wa_managed_phones filtered by various criteria"
    field :count_wa_managed_phones, :integer do
      arg(:filter, :wa_managed_phone_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WAManagedPhones.count_wa_managed_phones/3)
    end

    @desc "Fetch the QR / login screen for a managed phone so an admin can reconnect it"
    field :whatsapp_phone_screen, :wa_phone_screen_result do
      arg(:wa_managed_phone_id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.WAManagedPhones.whatsapp_phone_screen/3)
    end
  end

  object :wa_managed_phone_mutations do
    @desc "Log a managed phone out of WhatsApp so Maytapi issues a fresh QR to reconnect"
    field :reconnect_wa_managed_phone, :wa_managed_phone_result do
      arg(:wa_managed_phone_id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.WAManagedPhones.reconnect_wa_managed_phone/3)
    end

    @desc "Re-poll Maytapi and reconcile the stored status of every managed phone for the org"
    field :sync_wa_managed_phone_statuses, :wa_phone_status_sync_result do
      middleware(Authorize, :manager)
      resolve(&Resolvers.WAManagedPhones.sync_wa_managed_phone_statuses/3)
    end
  end
end
