defmodule GlificWeb.Schema.WaGroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's whatsapp Groups DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  alias Glific.Repo

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :wa_group_result do
    field :wa_group, :wa_group
    field :errors, list_of(:input_error)
  end

  @desc "Result of setPrimaryPhone. `warning` is set when the target phone's Maytapi status isn't 'active' so the UI can prompt for confirmation."
  object :set_primary_phone_result do
    field :primary_phone, :wa_group_phone
    field :warning, :string
    field :errors, list_of(:input_error)
  end

  @desc "Membership row linking a WAManagedPhone to a WAGroup. Exactly one row per group has `isPrimary: true`."
  object :wa_group_phone do
    field :id, :id
    field :is_primary, :boolean
    field :is_active, :boolean

    field :wa_managed_phone, :wa_managed_phone do
      resolve(dataloader(Repo))
    end
  end

  object :wa_group do
    field :id, :id
    field :label, :string
    field :bsp_id, :string

    field :last_communication_at, :datetime
    field :fields, :json

    @desc "The managed phone currently marked is_primary + is_active for this group. Nil if no primary is set."
    field :primary_phone, :wa_managed_phone do
      resolve(&Resolvers.WaGroup.primary_phone/3)
    end

    @desc "All wa_groups_phones membership rows for this group (active + inactive)."
    field :phones, list_of(:wa_group_phone) do
      resolve(dataloader(Repo, :wa_groups_phones))
    end

    field :groups, list_of(:group) do
      resolve(dataloader(Repo, use_parent: true))
    end
  end

  @desc "Filtering options for wa groups"
  input_object :wa_group_filter do
    @desc "Include wa_groups within these groups"
    field :include_groups, list_of(:id)

    @desc "Exclude wa_groups within these groups"
    field :exclude_groups, list_of(:id)

    @desc "term for the search"
    field :term, :string

    @desc "Searches based on wa group label"
    field :label, :string
  end

  input_object :wa_group_input do
    field :fields, :json
  end

  @desc "Input for createWaGroup. `numbers` are E.164 phone numbers without the +."
  input_object :create_wa_group_input do
    field :name, non_null(:string)
    field :wa_managed_phone_id, non_null(:id)
    field :numbers, list_of(:string)
  end

  object :wa_group_queries do
    @desc "get the details of one wa group"
    field :wa_group, :wa_group_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_group/3)
    end

    @desc "Get a list of all wa groups filtered by various criteria"
    field :wa_groups, list_of(:wa_group) do
      arg(:filter, :wa_group_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_groups/3)
    end

    field :wa_groups_count, :integer do
      arg(:filter, :wa_group_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_groups_count/3)
    end
  end

  object :wa_group_mutations do
    @desc "Promote a managed phone to the group's primary. Admin-only. Demote-then-promote runs in a single transaction."
    field :set_primary_phone, :set_primary_phone_result do
      arg(:wa_group_id, non_null(:id))
      arg(:wa_managed_phone_id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.WaGroup.set_primary_phone/3)
    end

    @desc "Create a new WhatsApp group via Maytapi using the chosen managed phone as the creator. Admin-only."
    field :create_wa_group, :wa_group_result do
      arg(:input, non_null(:create_wa_group_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.WaGroup.create_wa_group/3)
    end

    @desc "Rename a WhatsApp group via Maytapi (sets its subject). Admin-only."
    field :update_wa_group_subject, :wa_group_result do
      arg(:id, non_null(:id))
      arg(:wa_managed_phone_id, non_null(:id))
      arg(:subject, non_null(:string))
      middleware(Authorize, :admin)
      resolve(&Resolvers.WaGroup.update_wa_group_subject/3)
    end
  end
end
