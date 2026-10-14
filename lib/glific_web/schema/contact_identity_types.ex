defmodule GlificWeb.Schema.ContactIdentityTypes do
  @moduledoc """
  GraphQL types for a contact's login identities: the identity object, the lookup by identifier,
  and the mutation to create a contact together with its web login identifier.
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

  @desc "The web login identifier of a new contact, and optionally who they are"
  input_object :contact_identity_input do
    @desc "The username the contact logs in with; letters, digits, _, @ and ., stored lowercase so it is case-insensitive, 1 to 255 characters"
    field(:identifier, non_null(:string))

    @desc "The name to give the contact; defaults to the identifier"
    field(:name, :string)

    @desc "A WhatsApp phone number to link the contact to, if the number is already a contact"
    field(:phone, :string)
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
    @desc "Create the contact for a web login identifier before its first login, or return the existing one"
    field :create_contact_with_identity, :contact_result do
      arg(:input, non_null(:contact_identity_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.ContactIdentities.create_contact_with_identity/3)
    end
  end
end
