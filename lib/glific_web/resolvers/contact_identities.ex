defmodule GlificWeb.Resolvers.ContactIdentities do
  @moduledoc """
  Resolver for finding a contact by identity and adding an identity to a contact, between the
  GraphQL schema and `Glific.Contacts`.
  """

  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{Contacts, Contacts.Contact, Repo}
  alias GlificWeb.WebChannel.Flag

  @doc false
  @spec contact_by_identity(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_by_identity(_, %{channel: channel, identifier: identifier}, %{
        context: %{current_user: user}
      }) do
    case Contacts.fetch_by_identity(channel, identifier) do
      {:ok, %Contact{organization_id: organization_id} = contact}
      when organization_id == user.organization_id ->
        {:ok, %{contact: contact}}

      _not_found ->
        {:error, ["Contact", dgettext("errors", "Contact not found or permission denied.")]}
    end
  end

  @doc false
  @spec add_contact_identity(
          Absinthe.Resolution.t(),
          %{
            required(:contact_id) => integer(),
            required(:channel) => :whatsapp | :web,
            required(:identifier) => String.t(),
            optional(:optin) => boolean()
          },
          %{context: map()}
        ) :: {:ok, any} | {:error, any}
  def add_contact_identity(
        _,
        %{contact_id: contact_id, channel: channel, identifier: identifier} = args,
        %{context: %{current_user: user}}
      ) do
    with :ok <- check_channel_enabled(channel, user.organization_id),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         {:ok, contact} <- Contacts.add_identity(contact, channel, identifier),
         :ok <- record_web_optin(channel, identifier, args[:optin], "web_channel_api") do
      {:ok, %{contact: contact}}
    end
  end

  @doc """
  Records the web opt-in of `identifier` when the caller says the user consented (`optin` is `true`); `false` or
  absent records nothing, and never an opt-out. Other channels are not touched.
  """
  @spec record_web_optin(:whatsapp | :web, String.t() | nil, boolean() | nil, String.t()) ::
          :ok | {:error, any()}
  def record_web_optin(:web, identifier, true, method) do
    case Contacts.optin_contact(%{method: method}, :web, identifier) do
      {:ok, _contact} ->
        :ok

      {:error, _reason} ->
        {:error, ["Contact", dgettext("errors", "Could not record the web opt-in.")]}
    end
  end

  def record_web_optin(_channel, _identifier, _optin, _method), do: :ok

  @doc """
  Refuses a web identity while the web channel is off for the organization.
  """
  @spec check_channel_enabled(:whatsapp | :web, non_neg_integer()) :: :ok | {:error, any()}
  def check_channel_enabled(:web, organization_id) do
    if Flag.web_channel_enabled?(organization_id),
      do: :ok,
      else:
        {:error,
         [
           "Contact",
           dgettext("errors", "Web channel is not enabled for this organization.")
         ]}
  end

  def check_channel_enabled(_channel, _organization_id), do: :ok
end
