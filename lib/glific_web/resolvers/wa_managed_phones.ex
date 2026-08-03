defmodule GlificWeb.Resolvers.WAManagedPhones do
  @moduledoc """
  WAManagedPhone Resolver which sits between the GraphQL schema and Glific WAManagedPhone Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  @doc """
  Get the list of wa_managed_phones filtered by args
  """
  @spec wa_managed_phones(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [WAManagedPhone]}
  def wa_managed_phones(_, args, _) do
    {:ok, WAManagedPhones.list_wa_managed_phones(args)}
  end

  @doc """
  Get the count of wa_managed_phones filtered by args
  """
  @spec count_wa_managed_phones(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_wa_managed_phones(_, args, _) do
    {:ok, WAManagedPhones.count_wa_managed_phones(args)}
  end

  @doc """
  Fetch the QR / login screen for a managed phone so an admin can reconnect it.
  """
  @spec whatsapp_phone_screen(Absinthe.Resolution.t(), %{wa_managed_phone_id: integer}, %{
          context: map()
        }) :: {:ok, %{wa_phone_screen: map()}} | {:error, any}
  def whatsapp_phone_screen(_, %{wa_managed_phone_id: id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, screen} <- WAManagedPhones.fetch_phone_screen(user.organization_id, id) do
      {:ok, %{wa_phone_screen: screen}}
    end
  end

  @doc """
  Log a managed phone out of WhatsApp so Maytapi issues a fresh QR to reconnect.
  """
  @spec reconnect_wa_managed_phone(Absinthe.Resolution.t(), %{wa_managed_phone_id: integer}, %{
          context: map()
        }) :: {:ok, %{wa_managed_phone: WAManagedPhone.t()}} | {:error, any}
  def reconnect_wa_managed_phone(_, %{wa_managed_phone_id: id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, phone} <- WAManagedPhones.reconnect_wa_managed_phone(user.organization_id, id) do
      {:ok, %{wa_managed_phone: phone}}
    end
  end

  @doc """
  Re-poll Maytapi and reconcile the stored status of every managed phone for the org.
  """
  @spec sync_wa_managed_phone_statuses(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, %{message: String.t()}} | {:error, any}
  def sync_wa_managed_phone_statuses(_, _, %{context: %{current_user: user}}) do
    with :ok <- WAManagedPhones.reconcile_wa_managed_phone_statuses(user.organization_id) do
      {:ok, %{message: "WhatsApp phone statuses have been refreshed."}}
    end
  end
end
