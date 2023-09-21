defmodule GlificWeb.Resolvers.Contacts do
  @moduledoc """
  Contact Resolver which sits between the GraphQL schema and Glific Contact Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """
  import GlificWeb.Gettext

  alias Glific.{Contacts, Contacts.Contact, Contacts.Import, Repo, State}

  @doc false
  @spec contact(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact(_, %{id: id}, _context) do
    {:ok, %{contact: Contacts.get_contact!(id)}}
  rescue
    _ ->
      {:error, ["Contact", dgettext("errors", "Contact not found or permission denied.")]}
  end

  @doc false
  @spec contact_by_phone(Absinthe.Resolution.t(), %{phone: String.t()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_by_phone(_, %{phone: phone}, _context) do
    {:ok, %{contact: Contacts.get_contact_by_phone!(phone)}}
  rescue
    _ ->
      {:error, ["Contact", dgettext("errors", "Contact not found or permission denied.")]}
  end

  @doc false
  @spec contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def contacts(_, args, _) do
    {:ok, Contacts.list_contacts(args)}
  end

  @doc """
  Get the count of contacts filtered by args
  """
  @spec count_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_contacts(_, args, _) do
    {:ok, Contacts.count_contacts(args)}
  end

  @doc false
  @spec create_contact(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact(_, %{input: params}, _) do
    with {:ok, contact} <- Contacts.create_contact(params) do
      {:ok, %{contact: contact}}
    end
  end

  @doc false
  @spec update_contact(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}),
         {:ok, cleaned_params} <- clean_params(params),
         {:ok, contact} <- Contacts.update_contact(contact, cleaned_params) do
      {:ok, %{contact: contact}}
    end
  end

  @read_only_fields [:phone, :status, :bspStatus]

  @spec clean_params(map()) :: {:ok, map()} | {:error, String.t()}
  defp clean_params(params) do
    read_only_params = Map.take(params, @read_only_fields)

    if Map.keys(read_only_params) == [] do
      {:ok, params}
    else
      {:error, "Cannot modify read-only fields"}
    end
  end

  @doc """
  Import contacts to the database
  """
  @spec import_contacts(
          Absinthe.Resolution.t(),
          %{
            data: String.t(),
            id: integer,
            type: :data | :file_path | :url,
            group_label: String.t()
          },
          %{context: map()}
        ) :: any()

  def import_contacts(
        _,
        %{type: type, data: data, id: id, group_label: group_label} = _contact_attrs,
        %{context: %{current_user: user}}
      ) do
    organization_id = Glific.parse_maybe_integer(id) |> elem(1)

    Import.import_contacts(
      organization_id,
      %{user: user, collection: group_label},
      [{type, data}]
    )
  end

  @doc false
  @spec move_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def move_contacts(_, params, %{context: %{current_user: user}}) do
    Import.import_contacts(user.organization_id, %{user: user}, [{params.type, params.data}])
  end

  @doc false
  @spec delete_contact(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_contact(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}) do
      Contacts.delete_contact(contact)
    end
  end

  @doc """
  Get current location of the contact
  """
  @spec contact_location(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_location(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}) do
      Contacts.contact_location(contact)
    end
  end

  @doc """
  Upload a contact phone as opted in
  """
  @spec optin_contact(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def optin_contact(_, params, _) do
    with {:ok, contact} <- Contacts.optin_contact(params) do
      {:ok, %{contact: contact}}
    end
  end

  @doc """
  Release a simulator contact or nil if possible for this user
  """
  @spec contact_history(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_history(_, args, _) do
    {:ok, Contacts.list_contact_history(args)}
  end

  @doc """
  Release a simulator contact or nil if possible for this user
  """
  @spec count_contact_history(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def count_contact_history(_, args, _) do
    {:ok, Contacts.count_contact_history(args)}
  end

  @doc """
  Grab a simulator contact or nil if possible for this user
  """
  @spec simulator_get(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def simulator_get(_, _params, %{context: %{current_user: user}}) do
    {:ok, State.get_simulator(user)}
  end

  @doc """
  Release a simulator contact or nil if possible for this user
  """
  @spec simulator_release(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def simulator_release(_, _params, %{context: %{current_user: user}}) do
    {:ok, State.release_simulator(user)}
  end
end
