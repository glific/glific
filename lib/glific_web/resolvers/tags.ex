defmodule GlificWeb.Resolvers.Tags do
  @moduledoc """
  Tag Resolver which sits between the GraphQL schema and Glific Tag Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Tags, Tags.Tag}
  alias GlificWeb.Resolvers.Helper

  @doc """
  Get a specific tag by id
  """
  @spec tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tag(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, tag} <- Repo.fetch_by(Tag, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{tag: tag}}
  end

  @doc """
  Get the list of tags filtered by args
  """
  @spec tags(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Tag]}
  def tags(_, args, context) do
    {:ok, Tags.list_tags(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of tags filtered by args
  """
  @spec count_tags(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_tags(_, args, context) do
    {:ok, Tags.count_tags(Helper.add_org_filter(args, context))}
  end

  @doc false
  @spec create_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_tag(_, %{input: params}, _) do
    with {:ok, tag} <- Tags.create_tag(params) do
      {:ok, %{tag: tag}}
    end
  end

  @doc false
  @spec update_tag(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_tag(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, tag} <- Repo.fetch_by(Tag, %{id: id, organization_id: user.organization_id}),
         {:ok, tag} <- Tags.update_tag(tag, params) do
      {:ok, %{tag: tag}}
    end
  end

  @doc false
  @spec delete_tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_tag(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, tag} <- Repo.fetch_by(Tag, %{id: id, organization_id: user.organization_id}),
         {:ok, tag} <- Tags.delete_tag(tag) do
      {:ok, tag}
    end
  end

  @doc false
  @spec create_message_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_message_tag(_, %{input: params}, _) do
    with {:ok, message_tag} <- Tags.create_message_tag(params) do
      {:ok, %{message_tag: message_tag}}
    end
  end

  @doc false
  @spec update_message_tags(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_message_tags(_, %{input: params}, _) do
    # we should add sanity check whether message and tag belongs to the organization of the current user
    message_tags = Tags.MessageTags.update_message_tags(params)
    {:ok, message_tags}
  end

  @doc false
  @spec create_contact_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_tag(_, %{input: params}, _) do
    with {:ok, contact_tag} <- Tags.create_contact_tag(params) do
      {:ok, %{contact_tag: contact_tag}}
    end
  end

  @doc """
  Creates and/or deletes a list of contact tags, each tag attached to the same contact
  """
  @spec update_contact_tags(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact_tags(_, %{input: params}, _) do
    # we should add sanity check whether contact and tag belongs to the organization of the current user
    contact_tags = Tags.ContactTags.update_contact_tags(params)
    {:ok, contact_tags}
  end

  @doc false
  @spec mark_contact_messages_as_read(Absinthe.Resolution.t(), %{contact_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def mark_contact_messages_as_read(_, %{contact_id: contact_id}, _) do
    with untag_message_ids <- Tags.remove_tag_from_all_message(contact_id, "unread"),
         do: {:ok, untag_message_ids}
  end

  @doc """
  Create entry for tag mapped to template
  """
  @spec create_template_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_template_tag(_, %{input: params}, _) do
    with {:ok, template_tag} <- Tags.create_template_tag(params) do
      {:ok, %{template_tag: template_tag}}
    end
  end

  @doc """
  Creates and/or deletes a list of template tags, each tag attached to the same template
  """
  @spec update_template_tags(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_template_tags(_, %{input: params}, _) do
    # we should add sanity check whether template and tag belongs to the organization of the current user
    template_tags = Tags.TemplateTags.update_template_tags(params)
    {:ok, template_tags}
  end
end
