defmodule GlificWeb.Resolvers.Tags do
  @moduledoc """
  Tag Resolver which sits between the GraphQL schema and Glific Tag Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Contacts.Contact
  alias Glific.Messages.Message
  alias Glific.Templates.SessionTemplate
  alias Glific.{Messages, Repo, Tags, Tags.Tag}

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
  def tags(_, args, _) do
    {:ok, Tags.list_tags(args)}
  end

  @doc """
  Get the count of tags filtered by args
  """
  @spec count_tags(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_tags(_, args, _) do
    {:ok, Tags.count_tags(args)}
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
    with {:ok, tag} <- Repo.fetch_by(Tag, %{id: id, organization_id: user.organization_id}) do
      Tags.delete_tag(tag)
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
  def update_message_tags(_, %{input: params}, %{context: %{current_user: user}}) do
    with {:ok, _message} <-
           Repo.fetch_by(Message, %{id: params.message_id, organization_id: user.organization_id}) do
      message_tags =
        params
        |> scope_add_tag_ids(user.organization_id)
        |> Tags.MessageTags.update_message_tags()

      {:ok, message_tags}
    end
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
  def update_contact_tags(_, %{input: params}, %{context: %{current_user: user}}) do
    with {:ok, _contact} <-
           Repo.fetch_by(Contact, %{id: params.contact_id, organization_id: user.organization_id}) do
      contact_tags =
        params
        |> scope_add_tag_ids(user.organization_id)
        |> Tags.ContactTags.update_contact_tags()

      {:ok, contact_tags}
    end
  end

  @doc false
  @spec mark_contact_messages_as_read(Absinthe.Resolution.t(), %{contact_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def mark_contact_messages_as_read(_, %{contact_id: contact_id}, %{
        context: %{current_user: user}
      }) do
    Messages.mark_contact_messages_as_read(contact_id, user.organization_id)
    {:ok, contact_id}
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
  def update_template_tags(_, %{input: params}, %{context: %{current_user: user}}) do
    with {:ok, _template} <-
           Repo.fetch_by(SessionTemplate, %{
             id: params.template_id,
             organization_id: user.organization_id
           }) do
      template_tags =
        params
        |> scope_add_tag_ids(user.organization_id)
        |> Tags.TemplateTags.update_template_tags()

      {:ok, template_tags}
    end
  end

  @spec scope_add_tag_ids(map(), non_neg_integer()) :: map()
  defp scope_add_tag_ids(params, organization_id) do
    add_tag_ids = Repo.filter_ids_by_organization(Tag, params.add_tag_ids, organization_id)
    Map.put(params, :add_tag_ids, add_tag_ids)
  end
end
