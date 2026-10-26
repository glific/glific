defmodule GlificWeb.Resolvers.Contacts do
  @moduledoc """
  Contact Resolver which sits between the GraphQL schema and Glific Contact Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """
  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{Contacts, Contacts.Contact, Contacts.Import, Repo, State}
  alias GlificWeb.Resolvers.ContactIdentities

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
  def create_contact(_, %{input: params}, %{context: %{current_user: user}}) do
    with :ok <- check_channel(params, user.organization_id),
         {channel, params} = Map.pop(params, :channel, :whatsapp),
         {identifier, params} = Map.pop(params, :identifier),
         {:ok, contact} <- Contacts.create_contact(params, channel, identifier) do
      {:ok, %{contact: contact}}
    end
  end

  @spec check_channel(map(), non_neg_integer()) :: :ok | {:error, any()}
  defp check_channel(%{channel: :web} = params, organization_id) do
    with :ok <- ContactIdentities.check_channel_enabled(:web, organization_id) do
      if params[:identifier] in [nil, ""],
        do:
          {:error,
           ["Identifier", dgettext("errors", "Identifier is required for a web contact.")]},
        else: :ok
    end
  end

  defp check_channel(%{identifier: identifier}, _organization_id)
       when identifier not in [nil, ""],
       do:
         {:error, ["Identifier", dgettext("errors", "An identifier is only for a web contact.")]}

  defp check_channel(_params, _organization_id), do: :ok

  @doc false
  @spec update_contact(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}),
         {:ok, cleaned_params} <- validate_params(params),
         {:ok, contact} <- Contacts.update_contact(contact, cleaned_params) do
      {:ok, %{contact: contact}}
    end
  end

  @read_only_fields [:phone, :bspStatus, :channel, :identifier]

  @spec validate_params(map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_params(params) do
    param_keys = Map.keys(params)

    if Enum.any?(param_keys, fn param_key -> param_key in @read_only_fields end) do
      {:error, "Cannot modify read-only fields"}
    else
      {:ok, params}
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
        %{type: type, data: data, group_label: group_label} = _contact_attrs,
        %{context: %{current_user: user}}
      ) do
    Import.import_contacts(
      user.organization_id,
      %{user: user, collection: group_label, type: :import_contact},
      [{type, data}]
    )
  end

  @doc false
  @spec move_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def move_contacts(_, params, %{context: %{current_user: user}}) do
    Import.import_contacts(user.organization_id, %{user: user, type: :move_contact}, [
      {params.type, params.data}
    ])
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
  Opt a contact in on a channel: by phone on WhatsApp, by identifier on web
  """
  @spec optin_contact(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def optin_contact(_, params, _) do
    {channel, params} = Map.pop(params, :channel, :whatsapp)
    {identifier, params} = Map.pop(params, :identifier)

    with :ok <- ContactIdentities.check_channel_enabled(channel, params.organization_id),
         {:ok, contact} <-
           Contacts.contact_opted_in(
             Map.put_new(params, :phone, nil),
             params.organization_id,
             DateTime.utc_now(),
             channel: channel,
             identifier: identifier,
             method: optin_method(channel)
           ) do
      {:ok, %{contact: contact}}
    else
      {:error, :no_identifier} ->
        {:error,
         [
           "Identifier",
           dgettext("errors", "Identifier is required to opt in on the web channel.")
         ]}

      error ->
        error
    end
  end

  @spec optin_method(atom()) :: String.t()
  defp optin_method(:whatsapp), do: "BSP"
  defp optin_method(_channel), do: "API"

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

  @doc false
  @spec get_contact_upload_report(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_contact_upload_report(_, params, %{context: %{current_user: user}}) do
    Import.get_contact_upload_report(user.organization_id, params)
  end
end
