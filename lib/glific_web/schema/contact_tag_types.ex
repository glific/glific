defmodule GlificWeb.Schema.ContactTagTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Tag DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :contact_tag_result do
    field :contact_tag, :contact_tag
    field :errors, list_of(:input_error)
  end

  object :contact_tag do
    field :id, :id

    field :value, :string

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end
  end

  object :contact_tags do
    field :number_deleted, :integer
    field :contact_tags, list_of(:contact_tag)
  end

  input_object :contact_tag_input do
    field :contact_id, :id
    field :tag_id, :id
  end

  input_object :contact_tags_input do
    field :contact_id, non_null(:id)
    field :add_tag_ids, non_null(list_of(:id))
    field :delete_tag_ids, non_null(list_of(:id))
  end

  object :contact_tag_mutations do
    field :create_contact_tag, :contact_tag_result do
      arg(:input, non_null(:contact_tag_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Tags.create_contact_tag/3)
    end

    field :update_contact_tags, :contact_tags do
      arg(:input, non_null(:contact_tags_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Tags.update_contact_tags/3)
    end
  end

  object :contact_tag_subscriptions do
    field :created_contact_tag, :contact_tag do
      config(fn _args, _info ->
        {:ok, topic: :glific}
      end)

      resolve(fn contact_tag, _, _ -> {:ok, contact_tag} end)
    end

    field :deleted_contact_tag, :contact_tag do
      config(fn _args, _info ->
        {:ok, topic: :glific}
      end)

      trigger(
        [:delete_contact_tag],
        :glific
      )

      resolve(fn contact_tag, _, _ -> {:ok, contact_tag} end)
    end
  end
end
