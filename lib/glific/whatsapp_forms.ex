defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """
  require Logger

  alias Glific.{
    Providers.Gupshup.PartnerAPI,
    Providers.Gupshup.WhatsappForms.ApiClient,
    WhatsappForms.WhatsappForm
  }

  @doc """
  Creates a WhatsApp form
  """
  @spec create_whatsapp_form(map()) :: {:ok, map()} | {:error, any()}
  def create_whatsapp_form(attrs) do
    with {:ok, response} <- ApiClient.create_whatsapp_form(attrs),
         {:ok, db_attrs} <- prepare_db_attrs(attrs, response),
         {:ok, whatsapp_form} <- WhatsappForm.create_whatsapp_form(db_attrs),
         {:ok, _} <- maybe_set_subscription(attrs.organization_id) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_db_attrs(validated_attrs, api_response) do
    db_attrs = %{
      name: validated_attrs.name,
      organization_id: validated_attrs.organization_id,
      definition: validated_attrs.flow_json,
      meta_flow_id: Map.get(api_response, "id"),
      status: "draft",
      description: Map.get(validated_attrs, :description)
    }

    {:ok, db_attrs}
  end

  defp maybe_set_subscription(organization_id) do
    # Check if this is the first form for the organization
    case WhatsappForm.count_by_organization(organization_id) do
      1 ->
        case PartnerAPI.set_subscription(organization_id, nil, ["FLOW_MESSAGE"], 3) do
          {:ok, _response} ->
            {:ok, "subscription set"}

          {:error, error} ->
            Logger.error(
              "Failed to set subscription for org #{organization_id}: #{inspect(error)}"
            )
        end

      _ ->
        {:ok, "no subscription needed"}
    end
  end
end
