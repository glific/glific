defmodule GlificWeb.Schema.ContactTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactHistory,
    Repo
  }

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :contact_result do
    field(:contact, :contact)
    field(:errors, list_of(:input_error))
  end

  object :import_result do
    field(:status, :string)
    field(:errors, list_of(:input_error))
  end

  object :contact do
    field(:id, :id)
    field(:name, :string)

    field :masked_phone, :string do
      resolve(fn contact, _, _ ->
        masked_phone = Contact.populate_masked_phone(contact).masked_phone
        {:ok, masked_phone}
      end)
    end

    field :phone, :string do
      resolve(fn contact, _, %{context: %{current_user: user}} ->
        if Enum.member?(user.roles, :staff) && !user.is_restricted,
          do: {:ok, ""},
          else: {:ok, contact.phone}
      end)
    end

    field(:status, :contact_status_enum)
    field(:bsp_status, :contact_provider_status_enum)

    field :active_profile, :profile do
      resolve(dataloader(Repo))
    end

    field(:is_org_read, :boolean)
    field(:is_org_replied, :boolean)
    field(:is_contact_replied, :boolean)
    field(:last_message_number, :integer)

    field(:optin_time, :datetime)
    field(:optout_time, :datetime)

    field(:optin_method, :string)
    field(:optout_method, :string)

    field(:fields, :json)
    field(:settings, :json)

    field(:last_message_at, :datetime)
    field(:last_communication_at, :datetime)

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)

    field :language, :language do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :tags, list_of(:tag) do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :groups, list_of(:group) do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :history, list_of(:contact_history) do
      resolve(fn contact, _, _ ->
        contact_histories =
          ContactHistory
          |> where([ch], ch.contact_id == ^contact.id)
          |> order_by([ch], ch.event_datetime)
          |> Repo.all()

        {:ok, contact_histories}
      end)
    end
  end

  object :location do
    field(:longitude, :float)
    field(:latitude, :float)
  end

  object :contact_history do
    field(:id, :id)
    field(:event_type, :string)
    field(:event_label, :string)
    field(:event_meta, :json)
    field(:event_datetime, :datetime)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
    field :profile, :profile do
      resolve(dataloader(Repo, use_parent: true))
    end
  end

  @desc "Filtering options for contacts"
  input_object :contact_filter do
    @desc "Match the name"
    field(:name, :string)

    @desc "Match the phone"
    field(:phone, :string)

    @desc "Match the status"
    field(:status, :contact_status_enum)

    @desc "Match the bsp provider status"
    field(:bsp_status, :contact_provider_status_enum)

    @desc "Include contacts with these tags"
    field(:include_tags, list_of(:id))

    @desc "Include contacts with in these groups"
    field(:include_groups, list_of(:id))
  end

  @desc "Filtering options for search contacts"
  input_object :search_contacts_filter do
    @desc "Match the name"
    field(:name, :string)

    @desc "Match the phone"
    field(:phone, :string)

    @desc "Include contacts with these tags"
    field(:include_tags, list_of(:id))

    @desc "Include contacts with in these groups"
    field(:include_groups, list_of(:id))
  end

  input_object :contact_input do
    field(:name, :string)
    field(:phone, :string)
    field(:status, :contact_status_enum)
    field(:bsp_status, :contact_provider_status_enum)
    field(:language_id, :id)
    field(:active_profile_id, :id)
    field(:fields, :json)
    field(:settings, :json)
  end

  @desc "Filtering options for contacts history"
  input_object :contacts_history_filter do
    @desc "contact id"
    field(:contact_id, :id)

    @desc "Match the event type"
    field(:event_type, :string)

    @desc "Match the event label"
    field(:event_label, :string)

    @desc "profile id"
    field(:profile_id, :id)
  end

  object :contact_queries do
    @desc "get the details of one contact"
    field :contact, :contact_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.contact/3)
    end

    @desc "Get a contact information by phone"
    field :contact_by_phone, :contact_result do
      arg(:phone, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.contact_by_phone/3)
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

    @desc "Get a simulator contact for this user"
    field :simulator_get, :contact do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.simulator_get/3)
    end

    @desc "Release a simulator contact for this user"
    field :simulator_release, :contact do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.simulator_release/3)
    end

    @desc "Get a list of all contacts histroy filtered by various criteria"
    field :contact_history, list_of(:contact_history) do
      arg(:filter, :contacts_history_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.contact_history/3)
    end

    @desc "Get a count of all contacts histroy filtered by various criteria"
    field :count_contact_history, :integer do
      arg(:filter, :contacts_history_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.count_contact_history/3)
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

    field :optin_contact, :contact_result do
      arg(:phone, non_null(:string))
      arg(:name, :string)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Contacts.optin_contact/3)
    end

    field :import_contacts, :import_result do
      arg(:id, non_null(:id))
      arg(:type, :import_contacts_type_enum)
      arg(:group_label, non_null(:string))
      arg(:data, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.import_contacts/3)
    end
  end
end
