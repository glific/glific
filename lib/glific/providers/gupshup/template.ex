defmodule Glific.Providers.Gupshup.Template do
  @moduledoc """
  Messgae API layer between application and Gupshup
  """

  alias Glific.{
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Templates.SessionTemplate
  }

  @doc """
  Submitting HSM template for approval
  """
  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, String.t()}
  def submit_for_approval(attrs) do
    organization = Partners.organization(attrs.organization_id)

    with {:ok, response} <-
           ApiClient.submit_template_for_approval(
             attrs.organization_id,
             body(attrs, organization)
           ),
         {200, _response} <- {response.status, response} do
      {:ok, response_data} = Jason.decode(response.body)

      attrs
      |> Map.merge(%{
        number_parameter: length(Regex.split(~r/{{.}}/, attrs.body)) - 1,
        uuid: response_data["template"]["id"],
        status: response_data["template"]["status"],
        is_active:
          if(response_data["template"]["status"] == "APPROVED",
            do: true,
            else: false
          )
      })
      |> Glific.Templates.do_create_session_template()
    else
      {status, response} ->
        # structure of response body can be different for different errors
        {:error, ["BSP response status: #{to_string(status)}", response.body]}

      _ ->
        {:error, ["BSP", "couldn't submit for approval"]}
    end
  end

  @doc """
  Updating HSM templates for an organization
  """
  @spec update_hsm_templates(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsm_templates(organization_id) do
    organization = Partners.organization(organization_id)

    with {:ok, response} <-
           ApiClient.get_templates(organization_id),
         {:ok, response_data} <- Jason.decode(response.body),
         false <- is_nil(response_data["templates"]) do
      Glific.Templates.do_update_hsms(response_data["templates"], organization)
      :ok
    else
      _ ->
        {:error, ["BSP", "couldn't connect"]}
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
      content: attrs.body,
      category: attrs.category,
      vertical: attrs.label,
      templateType: String.upcase(Atom.to_string(attrs.type)),
      example: attrs.example
    }
  end
end
