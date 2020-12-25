defmodule Glific.Providers.Gupshup.Template do
  @moduledoc """
  Messgae API layer between application and Gupshup
  """

  alias Glific.{
    Partners,
    Providers.Gupshup.ApiClient
  }

  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, String.t()}
  def submit_for_approval(attrs) do
    organization = Partners.organization(attrs.organization_id)
    bsp_creds = organization.services["bsp"]
    api_key = bsp_creds.secrets["api_key"]
    template_url = bsp_creds.keys["api_end_point"] <> "/template/add/" <> bsp_creds.secrets["app_name"]

    with {:ok, response} <- ApiClient.post(template_url, body(attrs, organization), headers: [{"apikey", api_key}]),
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

  @spec update_hsm_templates(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsm_templates(organization_id) do
    organization = Partners.organization(organization_id)
    bsp_creds = organization.services["bsp"]
    api_key = bsp_creds.secrets["api_key"]
    template_url = bsp_creds.keys["api_end_point"] <> "/template/list/" <> bsp_creds.secrets["app_name"]

    with {:ok, response} <-
        ApiClient.get(template_url, headers: [{"apikey", api_key}]),
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
      vertical: attrs.shortcode,
      templateType: String.upcase(Atom.to_string(attrs.type)),
      example: attrs.example
    }
  end


end
