defmodule Glific.Providers.Gupshup.GupshupWallet do
  @moduledoc """
  Module for checking gupshup remaining balance
  """
  alias Glific.Providers.Gupshup.PartnerAPI
  use Gettext, backend: GlificWeb.Gettext

  @doc """
  function for making call to gupshup for remaining balance
  """
  @spec balance(non_neg_integer()) :: {:ok, any()} | {:error, String.t()}
  def balance(org_id) do
    PartnerAPI.get_balance(org_id)
  end
end
