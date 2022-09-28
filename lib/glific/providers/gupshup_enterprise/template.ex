defmodule Glific.Providers.GupshupEnterprise.Template do
  @moduledoc """
  Module for handling template operations specific to Gupshup
  """

  alias Glific.{
    Partners,
    Repo,
    Settings.Language,
    Templates
  }

  @template_status %{
    "ENABLED" => "APPROVED",
    "REJECTED" => "REJECTED"
  }

  @doc """
  Import pre approved templates when BSP is GupshupEnterprise
  """
  @spec import_templates(non_neg_integer(), String.t()) :: {:ok, any}
  def import_templates(organization_id, data) do
    {:ok, stream} = StringIO.open(data)
    organization = Partners.organization(organization_id)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(headers: true, strip_fields: true)
    |> Enum.map(fn {_, data} -> import_approved_templates(data) end)
    |> Templates.update_hsms(organization)

    {:ok, %{message: "All templates have been added"}}
  end

  @doc """
  Updating HSM templates for an organization
  """
  @spec update_hsm_templates(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsm_templates(_organization_id) do
    ## We still need to implement this functionality.
    ## Currently it's just for the same behaviour perspective
    ## so that we don't face any issue while fetching the hsm templates
    :ok
  end

  @doc """
  Delete template from the gupshup
  """
  @spec delete(non_neg_integer(), map()) :: {:ok, any()} | {:error, any()}
  def delete(_org_id, attrs) do
    {:ok, attrs}
  end

  @spec import_approved_templates(map()) :: map()
  defp import_approved_templates(template) do
    updated_body = check_for_button_template(template, template["BUTTONTYPE"])

    %{
      "id" => Ecto.UUID.generate(),
      "data" => updated_body,
      "meta" => get_example_body(template["BODY"]),
      "category" => "TRANSACTIONAL",
      "elementName" => template["NAME"],
      "languageCode" => get_language(template["LANGUAGE"]),
      "templateType" => template["TYPE"],
      "status" => Map.get(@template_status, template["STATUS"], "PENDING"),
      "bsp_id" => template["TEMPLATEID"]
    }
  end

  @spec check_for_button_template(map(), String.t()) :: String.t()
  def check_for_button_template(template, "NONE"), do: template["BODY"]

  def check_for_button_template(template, "QUICK_REPLY") do
    button_list = [template["BUTTON1"]] ++ [template["BUTTON2"]] ++ [template["BUTTON3"]]

    button_text =
      Enum.reduce(button_list, "", fn button, acc ->
        if button == "" do
          acc <> ""
        else
          parsed_button = Jason.decode!(button)
          acc <> " | " <> "[#{parsed_button["text"]}]"
        end
      end)

    template["BODY"] <> button_text
  end

  @spec get_language(String.t()) :: String.t()
  defp get_language(label_locale) do
    Repo.fetch_by(Language, %{label_locale: label_locale})
    |> case do
      {:ok, language} -> language.locale
      # Setting en as default locale
      {:error, _language} -> "en"
    end
  end

  @spec get_example_body(String.t()) :: String.t()
  defp get_example_body(body) do
    body
    |> String.replace("{{", "[sample text ")
    |> String.replace("}}", "]")
    |> then(&Map.put(%{}, :example, &1))
    |> Jason.encode!()
  end
end
