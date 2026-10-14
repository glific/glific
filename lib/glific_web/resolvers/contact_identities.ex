defmodule GlificWeb.Resolvers.ContactIdentities do
  @moduledoc """
  Resolver for finding and creating contacts by login identity, between the GraphQL schema and
  `Glific.Contacts.Identities`.
  """

  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{Contacts, Contacts.Identities}
  alias GlificWeb.WebChannel.Flag

  @max_length 255

  @doc false
  @spec contact_by_identity(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_by_identity(_, %{channel: channel, identifier: identifier}, _context) do
    case Contacts.fetch_by_identity(channel, identifier) do
      {:ok, contact} ->
        {:ok, %{contact: contact}}

      {:error, _reason} ->
        {:error, ["Contact", dgettext("errors", "Contact not found or permission denied.")]}
    end
  end

  @doc false
  @spec create_contact_with_identity(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_with_identity(_, %{input: input}, %{context: %{current_user: user}}) do
    with :ok <- check_enabled(user.organization_id),
         {:ok, identifier} <- check_identifier(input.identifier),
         {:ok, contact} <- Identities.resolve_or_create(:web, identifier, claims(input)) do
      {:ok, %{contact: contact}}
    end
  end

  @spec check_enabled(non_neg_integer()) :: :ok | {:error, any()}
  defp check_enabled(organization_id) do
    if Flag.web_channel_enabled?(organization_id),
      do: :ok,
      else:
        {:error,
         [
           "Contact",
           dgettext("errors", "Web channel is not enabled for this organization.")
         ]}
  end

  @spec check_identifier(String.t()) :: {:ok, String.t()} | {:error, any()}
  defp check_identifier(identifier) do
    if String.length(identifier) in 1..@max_length,
      do: {:ok, identifier},
      else:
        {:error,
         ["Identifier", dgettext("errors", "Identifier must be 1 to 255 characters long.")]}
  end

  @spec claims(map()) :: Identities.claims()
  defp claims(input) do
    %{name: input[:name], phone: normalised_phone(input[:phone])}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec normalised_phone(String.t() | nil) :: String.t() | nil
  defp normalised_phone(nil), do: nil

  defp normalised_phone(phone) do
    case Contacts.parse_phone_number(phone) do
      {:ok, normalised} -> normalised
      {:error, _reason} -> nil
    end
  end
end
