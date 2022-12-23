defmodule Glific.Providers.Airtel.Template do
  @moduledoc """
  Module for handling template operations specific to Airtel
  """

  @behaviour Glific.Providers.TemplateBehaviour

  alias Glific.{
    Templates,
    Templates.SessionTemplate
  }

  require Logger

  @doc """
  Submitting HSM template for approval
  """
  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, any()}
  def submit_for_approval(attrs),
    do: {:ok, Templates.get_session_template!(attrs.id)}

  @doc """
  Import pre approved templates when BSP is GupshupEnterprise
  """
  @spec import_templates(non_neg_integer(), String.t()) :: {:ok, any}
  def import_templates(_organization_id, _data) do
    {:ok, %{message: "Feature not available"}}
  end

  @doc """
  Delete template from the Airtel
  """
  @spec delete(non_neg_integer(), map()) :: {:ok, any()} | {:error, any()}
  def delete(_org_id, _attrs) do
    {:ok, "Coming soon"}
  end

  @doc """
  Updating HSM templates for an organization
  """
  @spec update_hsm_templates(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsm_templates(_org_id) do
    :ok
  end
end
