defmodule Glific.Providers.Gupshup.Template do
  @moduledoc """
  Module for handling template operations specific to Gupshup
  """

  @behaviour Glific.Providers.TemplateBehaviour

  alias Glific.{
    Messages.MessageMedia,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Providers.Gupshup.PartnerAPI,
    Repo,
    Templates,
    Templates.SessionTemplate
  }

  require Logger

  @doc """
  Submitting HSM template for approval
  """
  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, String.t()}
  def submit_for_approval(attrs) do
    organization = Partners.organization(attrs.organization_id)

    PartnerAPI.apply_for_template(
      attrs.organization_id,
      body(attrs, organization)
    )
    |> case do
      {:ok, %{"template" => template} = _response} ->
        attrs
        |> Map.merge(%{
          number_parameters: Templates.template_parameters_count(attrs),
          uuid: template["id"],
          bsp_id: template["id"],
          status: template["status"],
          is_active: template["status"] == "APPROVED"
        })
        |> append_buttons(attrs)
        |> Templates.do_create_session_template()

      {:error, error} ->
        Logger.error(error)
        {:error, ["BSP", "couldn't submit for approval"]}

      other_response ->
        other_response
    end
  end

  @doc """
  Import pre approved templates when BSP is GupshupEnterprise
  """
  @spec import_templates(non_neg_integer(), String.t()) :: {:ok, any}
  def import_templates(_organization_id, _data) do
    {:ok, %{message: "Feature not available"}}
  end

  @doc """
  Delete template from the gupshup
  """
  @spec delete(non_neg_integer(), map()) :: {:ok, any()} | {:error, any()}
  def delete(org_id, attrs) do
    PartnerAPI.delete_hsm_template(org_id, attrs.shortcode)
    |> case do
      {:ok, res} ->
        {:ok, res}

      {:error, error} ->
        Logger.error("Error while deleting the template. #{inspect(error)}")
        {:error, error}
    end
  end

  @spec append_buttons(map(), map()) :: map()
  defp append_buttons(template, %{has_buttons: true} = attrs),
    do: template |> Map.merge(%{buttons: attrs.buttons})

  defp append_buttons(template, _attrs), do: template

  @doc """
  Updating HSM templates for an organization
  """
  @spec update_hsm_templates(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsm_templates(org_id) do
    organization = Partners.organization(org_id)

    with {:ok, response} <-
           ApiClient.get_templates(org_id),
         {:ok, response_data} <- Jason.decode(response.body),
         false <- is_nil(response_data["templates"]) do
      response_data["templates"]
      |> Enum.reduce([], &(&2 ++ [Map.put(&1, "bsp_id", &1["id"])]))
      |> Templates.update_hsms(organization)

      :ok
    else
      _ ->
        {:error, "BSP Couldn't connect"}
    end
  end

  @spec body(map(), Organization.t()) :: map()
  defp body(attrs, organization) do
    language =
      Enum.find(organization.languages, fn language ->
        to_string(language.id) == to_string(attrs.language_id)
      end)

    %{
      elementName: attrs.shortcode,
      languageCode: language.locale,
      category: attrs.category,
      vertical: attrs.label,
      templateType: String.upcase(Atom.to_string(attrs.type)),
      content: attrs.body,
      example: attrs.example,
      enableSample: true
    }
    |> attach_media_params(attrs)
    |> attach_button_param(attrs)
  end

  defp attach_media_params(template_payload, %{type: :text} = _attrs), do: template_payload

  defp attach_media_params(template_payload, %{type: _type} = attrs) do
    media_id = Glific.parse_maybe_integer!(attrs[:message_media_id])
    {:ok, media} = Repo.fetch_by(MessageMedia, %{id: media_id})

    media_handle_id =
      PartnerAPI.get_media_handle_id(
        attrs.organization_id,
        media.url,
        Atom.to_string(attrs.type)
      )

    template_payload
    |> Map.merge(%{
      enableSample: true,
      exampleMedia: media_handle_id
    })
  end

  @spec attach_button_param(map(), map()) :: map()
  defp attach_button_param(template_payload, %{has_buttons: true, buttons: buttons}) do
    Map.merge(template_payload, %{buttons: Jason.encode!(buttons)})
  end

  defp attach_button_param(template_payload, _attrs), do: template_payload
end
