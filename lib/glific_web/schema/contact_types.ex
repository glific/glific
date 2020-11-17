defmodule GlificWeb.Schema.ContactTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.{
    Contacts.Contact,
    Repo
  }

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :contact_result do
    field :contact, :contact
    field :errors, list_of(:input_error)
  end

  object :contact do
    field :id, :id

    field :masked_phone, :string do
      resolve(fn contact, _, _ ->
        masked_phone = Contact.populate_masked_phone(contact).masked_phone
        {:ok, masked_phone}
      end)
    end

    field :phone, :string do
      resolve(fn contact, _, %{context: %{current_user: user}} ->
        if Enum.member?(user.roles, :staff),
          do: {:ok, ""},
          else: {:ok, contact.phone}
      end)

    field :status, :contact_status_enum
    field :bsp_status, :contact_provider_status_enum

    field :optin_time, :datetime
    field :optout_time, :datetime

    field :fields, :json
    field :settings, :json

    field :last_message_at, :datetime

    field :language, :language do
      resolve(dataloader(Repo))
    end

    field :tags, list_of(:tag) do
      resolve(dataloader(Repo))
    end

    field :groups, list_of(:group) do
      resolve(dataloader(Repo))
    end
  end

  object :location do
    field :longitude, :float
    field :latitude, :float
  end

  @desc "Filtering options for contacts"
  input_object :contact_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the phone"
    field :phone, :string

    @desc "Match the status"
    field :status, :contact_status_enum

    @desc "Match the bsp provider status"
    field :bsp_status, :contact_provider_status_enum

    @desc "Include contacts with these tags"
    field :include_tags, list_of(:id)

    @desc "Include contacts with in these groups"
    field :include_groups, list_of(:id)
  end

  @desc "Filtering options for search contacts"
  input_object :search_contacts_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the phone"
    field :phone, :string

    @desc "Include contacts with these tags"
    field :include_tags, list_of(:id)

    @desc "Include contacts with in these groups"
    field :include_groups, list_of(:id)
  end

  input_object :contact_input do
    field :name, :string
    field :phone, :string
    field :status, :contact_status_enum
    field :bsp_status, :contact_provider_status_enum
    field :language_id, :id
    field :fields, :json
    field :settings, :json
  end

  object :contact_queries do
    @desc "get the details of one contact"
    field :contact, :contact_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.contact/3)
    end

    @desc "Get a list of all contacts filtered by various criteria"
    field :contacts, list_of(:contact) do
      arg(:filter, :contact_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.contacts/3)
    end

    @desc "Get a count of all contacts filtered by various criteria"
    field :count_contacts, :integer do
      arg(:filter, :contact_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.count_contacts/3)
    end

    @desc "Get contact's current location"
    field :contact_location, :location do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Contacts.contact_location/3)
    end
  end

  object :contact_mutations do
    field :create_contact, :contact_result do
      arg(:input, non_null(:contact_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Contacts.create_contact/3)
    end

    field :update_contact, :contact_result do
      arg(:id, non_null(:id))
      arg(:input, :contact_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.update_contact/3)
    end

    field :delete_contact, :contact_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Contacts.delete_contact/3)
    end
  end
end
