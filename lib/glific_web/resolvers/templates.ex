defmodule GlificWeb.Resolvers.Templates do
  @moduledoc """
  Templates Resolver which sits between the GraphQL schema and Glific Templates Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Communications.Message, as: Communications
  alias Glific.{Repo, Templates, Templates.SessionTemplate}

  @doc """
  Get a specific session template by id
  """
  @spec session_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def session_template(_, %{id: id}, _) do
    with {:ok, session_template} <- Repo.fetch(SessionTemplate, id),
         do: {:ok, %{session_template: session_template}}
  end

  @doc """
  Get the list of session templates filtered by args
  """
  @spec session_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def session_templates(_, args, _) do
    {:ok, Templates.list_session_templates(args)}
  end

  @doc """
  Get the count of sessiont templates filtered by args
  """
  @spec count_session_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_session_templates(_, args, _) do
    {:ok, Templates.count_session_templates(args)}
  end

  @doc false
  @spec create_session_template(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_session_template(_, %{input: params}, _) do
    with {:ok, session_template} <- Templates.create_session_template(params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec update_session_template(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_session_template(_, %{id: id, input: params}, _) do
    with {:ok, session_template} <- Repo.fetch(SessionTemplate, id),
         {:ok, session_template} <- Templates.update_session_template(session_template, params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec delete_session_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_session_template(_, %{id: id}, _) do
    with {:ok, session_template} <- Repo.fetch(SessionTemplate, id),
         {:ok, session_template} <- Templates.delete_session_template(session_template) do
      {:ok, session_template}
    end
  end

  @doc false
  @spec send_session_message(Absinthe.Resolution.t(), %{id: integer, receiver_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def send_session_message(_, %{id: id, receiver_id: receiver_id}, _) do
    {:ok, session_template} = Repo.fetch(SessionTemplate, id)
    {:ok, receiver} = Repo.fetch(Glific.Contacts.Contact, receiver_id)

    message_params = %{
      body: session_template.body,
      type: session_template.type,
      media_id: session_template.message_media_id,
      sender_id: Glific.Communications.Message.organization_contact_id(),
      receiver_id: receiver.id,
      contact_id: receiver.id
    }

    with {:ok, message} <- Glific.Messages.create_message(message_params) do
      send_message(message)
    end
  end

  @spec send_message(Glific.Messages.Message.t()) :: {:ok, any}
  defp send_message(message) do
    message
    |> Repo.preload([:receiver, :sender, :media])
    |> Communications.send_message()

    Communications.publish_message({:ok, message}, :sent_message)
    {:ok, %{message: message}}
  end
end
