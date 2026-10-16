defmodule GlificWeb.Resolvers.ContactIdentities do
  @moduledoc """
  Resolver for adding an identity to a contact, between the GraphQL schema and
  `Glific.Contacts`.
  """

  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{Contacts, Contacts.Contact, Repo}
  alias GlificWeb.WebChannel.Flag

  @doc false
  @spec add_contact_identity(
          Absinthe.Resolution.t(),
          %{contact_id: integer(), channel: :whatsapp | :web, identifier: String.t()},
          %{context: map()}
        ) :: {:ok, any} | {:error, any}
  def add_contact_identity(
        _,
        %{contact_id: contact_id, channel: channel, identifier: identifier},
        %{context: %{current_user: user}}
      ) do
    with :ok <- check_channel_enabled(channel, user.organization_id),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         {:ok, contact} <- Contacts.add_identity(contact, channel, identifier) do
      {:ok, %{contact: contact}}
    end
  end

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
