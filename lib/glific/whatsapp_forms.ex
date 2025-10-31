defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """

  alias Glific.{
    Enums.WhatsappFormCategory,
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
         {:ok, whatsapp_form} <- WhatsappForm.create_whatsapp_form(db_attrs) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all available WhatsApp form categories
  """
  @spec list_whatsapp_form_categories() :: {:ok, list(String.t())}
  def list_whatsapp_form_categories() do
    categories =
      WhatsappFormCategory.__enum_map__()
      |> Enum.map(fn key -> key |> Atom.to_string() |> String.upcase() end)
    {:ok, categories}
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
end
