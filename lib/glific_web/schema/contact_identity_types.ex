defmodule GlificWeb.Schema.ContactIdentityTypes do
  @moduledoc """
  GraphQL types for a contact's login identities: the identity object, the lookup by identifier,
  and the mutation to add an identity to a contact.
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  @desc "How a contact logs in on a channel"
  object :contact_identity do
    field(:id, :id)
    field(:channel, :message_channel_enum)
    field(:identifier, :string)
    field(:inserted_at, :datetime)
  end

  object :contact_identity_queries do
    @desc "Get the contact that logs in with an identifier on a channel; web identifiers are case-insensitive"
    field :contact_by_identity, :contact_result do
      arg(:channel, non_null(:message_channel_enum))
      arg(:identifier, non_null(:string))
      middleware(Authorize, :manager)
      resolve(&Resolvers.ContactIdentities.contact_by_identity/3)
    end
  end

  object :contact_identity_mutations do
    @desc "Add a login identity, such as a web username, to a contact"
    field :add_contact_identity, :contact_result do
      arg(:contact_id, non_null(:id))
      arg(:channel, non_null(:message_channel_enum))
      arg(:identifier, non_null(:string))
      middleware(Authorize, :manager)
      resolve(&Resolvers.ContactIdentities.add_contact_identity/3)
    end
  end
end
