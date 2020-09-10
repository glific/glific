defmodule GlificWeb.Schema.TemplateTagTypes do
  @moduledoc """
  GraphQL Representation of Glific's Template Tag DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :template_tag_result do
    field :template_tag, :template_tag
    field :errors, list_of(:input_error)
  end

  object :template_tag do
    field :id, :id

    field :value, :string

    field :template, :session_template do
      resolve(dataloader(Repo))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end
  end

  object :template_tags do
    field :number_deleted, :integer
    field :template_tags, list_of(:template_tag)
  end

  input_object :template_tag_input do
    field :template_id, :id
    field :tag_id, :id
  end

  input_object :template_tags_input do
    field :template_id, non_null(:id)
    field :add_tag_ids, non_null(list_of(:id))
    field :delete_tag_ids, non_null(list_of(:id))
  end

  object :template_tag_mutations do
    field :create_template_tag, :template_tag_result do
      arg(:input, non_null(:template_tag_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Tags.create_template_tag/3)
    end

    field :update_template_tags, :template_tags do
      arg(:input, non_null(:template_tags_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Tags.update_template_tags/3)
    end
  end

  object :template_tag_subscriptions do
    field :created_template_tag, :template_tag do
      config(fn _args, _info ->
        {:ok, topic: :glific}
      end)

      resolve(fn template_tag, _, _ -> {:ok, template_tag} end)
    end

    field :deleted_template_tag, :template_tag do
      config(fn _args, _info ->
        {:ok, topic: :glific}
      end)

      trigger(
        [:delete_template_tag],
        :glific
      )

      resolve(fn template_tag, _, _ -> {:ok, template_tag} end)
    end
  end
end
