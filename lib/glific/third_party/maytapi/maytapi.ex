defmodule Glific.Maytapi do
  @moduledoc """
  Glific Maytapi integration to send whatsapp group messages
  """

  alias Glific.Partners

  @doc false
  @spec fetch_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_credentials(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["maytapi"]
    |> case do
      nil ->
        {:error, "Maytapi is not active"}

      credentials ->
        credentials.secrets
    end
  end
end
