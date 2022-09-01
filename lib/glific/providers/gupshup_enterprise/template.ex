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
    "Enabled" => "APPROVED",
    "Rejected" => "REJECTED"
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
  Delete template from the gupshup
  """
  @spec delete(non_neg_integer(), map()) :: {:ok, any()} | {:error, any()}
  def delete(_org_id, attrs) do
    {:ok, attrs}
  end

  @spec import_approved_templates(map()) :: map()
  defp import_approved_templates(template),
    do: %{
      "id" => Ecto.UUID.generate(),
      "data" => template["Body"],
      "meta" => get_example_body(template["Body"]),
      "category" => "TRANSACTIONAL",
      "elementName" => template["Template Name"],
      "languageCode" => get_language(template["Language"]),
      "templateType" => template["Type"],
      "status" => Map.get(@template_status, template["Status"], "PENDING"),
      "bsp_id" => template["Template Id"]
    }

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
