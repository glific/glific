defmodule Glific.Providers.Gupshup.Template do
  @moduledoc """
  Module for handling template operations specific to Gupshup
  """

  @behaviour Glific.Providers.TemplateBehaviour
  @languages [
    "Tamil",
    "Kannada",
    "Malayalam",
    "Telugu",
    "Odia",
    "Assamese",
    "Gujarati",
    "Bengali",
    "Punjabi",
    "Marathi",
    "Urdu",
    "Spanish",
    "Hindi",
    "English",
    "Sign Language"
  ]

  alias Glific.{
    Messages,
    Messages.MessageMedia,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Providers.Gupshup.PartnerAPI,
    Repo,
    Settings.Language,
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
  Import pre approved templates when BSP is Gupshup
  """
  @spec import_templates(non_neg_integer(), String.t()) :: {:ok, any}
  def import_templates(_organization_id, _data) do
    {:ok, %{message: "Feature not available"}}
  end

  @doc """
  Bulk apply templates from CSV when BSP is Gupshup
  Glific.Providers.Gupshup.Template.bulk_apply_templates(1, data)
  """
  @spec bulk_apply_templates(non_neg_integer(), String.t()) :: {:ok, any}
  def bulk_apply_templates(organization_id, data) do
    {:ok, stream} = StringIO.open(data)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(headers: true, strip_fields: true)
    |> Enum.map(fn {_, data} -> process_templates(organization_id, data) end)

    {:ok, %{message: "All templates have been applied"}}
  end

  @spec process_templates(non_neg_integer(), map()) ::
          {String.t(), map()} | {String.t(), String.t()}
  defp process_templates(org_id, template) do
    with {:ok, template} <- validate_dropdowns(template),
         {:ok, language} <- Repo.fetch_by(Language, %{label_locale: template["Language"]}) do
      %{
        body: template["Message"],
        category: template["Category"],
        example: template["Sample Message"],
        is_active: true,
        is_hsm: true,
        label: template["Title"],
        language_id: language.id,
        organization_id: org_id,
        shortcode: template["Element Name"],
        translations: %{}
      }
      |> check_media_template(template, org_id)
      |> process_buttons(template["Has Buttons"], template)
    end
  end

  defp check_media_template(template, %{"Attachment Type" => type} = csv_template, org_id)
       when type in ["image", "video", "document"] do
    {:ok, message_media} =
      %{
        url: csv_template["Attachment URL"],
        source_url: csv_template["Attachment URL"],
        organization_id: org_id
      }
      |> Messages.create_message_media()

    {media_type, _url} = Messages.get_media_type_from_url(csv_template["Attachment URL"])

    template
    |> Map.put(:media_id, message_media.id)
    |> Map.put(:type, media_type)
  end

  defp check_media_template(template, _type, _org_id) do
    template
    |> Map.put(:type, :text)
  end

  @spec process_buttons(map(), String.t(), map()) :: {String.t(), map()}
  defp process_buttons(template, "FALSE", csv_template), do: {csv_template["Title"], template}

  defp process_buttons(template, "TRUE", csv_template) do
    case csv_template["Button Type"] do
      "QUICK_REPLY" ->
        buttons =
          [
            csv_template["Quick Reply 1 Title"],
            csv_template["Quick Reply 2 Title"],
            csv_template["Quick Reply 3 Title"]
          ]
          |> Enum.reduce([], fn quick_reply, acc ->
            if quick_reply != "",
              do: acc ++ [%{"text" => quick_reply, "type" => "QUICK_REPLY"}],
              else: acc
          end)

        template
        |> Map.put(:buttons, buttons)
        |> Map.put(:button_type, :quick_reply)
        |> then(&{csv_template["Title"], &1})

      "CALL_TO_ACTION" ->
        buttons =
          [
            {csv_template["CTA Button 1 Title"], csv_template["CTA Button 1 Type"],
             csv_template["CTA Button 1 Value"]},
            {csv_template["CTA Button 2 Title"], csv_template["CTA Button 2 Type"],
             csv_template["CTA Button 2 Value"]}
          ]
          |> Enum.map(fn {title, type, value} ->
            if type == "PHONE NUMBER" do
              %{"text" => title, "type" => type, "phone_number" => value}
            else
              %{"text" => title, "type" => type, "url" => value}
            end
          end)

        template
        |> Map.put(:buttons, buttons)
        |> Map.put(:button_type, :call_to_action)
        |> then(&{csv_template["Title"], &1})
    end
  end

  @spec validate_dropdowns(map()) :: {:ok, map()} | {String.t(), String.t()}
  defp validate_dropdowns(template) do
    with true <- is_valid_language?(template["Language"]),
         true <- is_valid_category?(template["Category"]),
         true <- has_valid_buttons?(template["Has Buttons"], template),
         true <- is_valid_shortcode?(template["Element Name"]),
         true <- is_valid_media?(template["Attachment Type"], template["Attachment URL"]) do
      {:ok, template}
    else
      {_, error} ->
        {template["Title"], error}
    end
  end

  @spec is_valid_language?(String.t()) :: true | {:error, String.t()}
  defp is_valid_language?(language) when language in @languages, do: true
  defp is_valid_language?(_language), do: {:error, "Invalid Language"}

  @spec is_valid_category?(String.t()) :: true | {:error, String.t()}
  defp is_valid_category?(category) when category in ["TRANSACTIONAL", "MARKETING", "OTP"],
    do: true

  defp is_valid_category?(_category), do: {:error, "Invalid Category"}

  @spec is_valid_shortcode?(String.t()) :: true | {:error, String.t()}
  defp is_valid_shortcode?(shortcode) do
    if String.match?(shortcode, ~r/^[a-z0-9_]*$/),
      do: true,
      else: {:error, "Invalid Element Name"}
  end

  @spec is_valid_media?(String.t(), String.t()) :: true | {:error, String.t()}
  defp is_valid_media?(type, url) when type in ["image", "video", "document"] do
    %{is_valid: is_valid} = Messages.validate_media(url, type)
    if is_valid, do: true, else: {:error, "Invalid Attachment URL"}
  end

  defp is_valid_media?(type, _url) when type == "", do: true

  defp is_valid_media?(_type, _url), do: {:error, "Invalid Attachment Type"}

  @spec has_valid_buttons?(String.t(), map()) :: true | {:error, String.t()}
  defp has_valid_buttons?("FALSE", _template), do: true

  defp has_valid_buttons?("TRUE", template) do
    case template["Button Type"] do
      "CALL_TO_ACTION" ->
        if template["CTA Button 1 Type"] in ["Phone Number", "URL"] &&
             template["CTA Button 2 Type"] in ["Phone Number", "URL"] do
          true
        else
          {:error, "Invalid Call To Action Button type"}
        end

      "QUICK_REPLY" ->
        if is_empty?(template["Quick Reply 1 Title"]) &&
             is_empty?(template["Quick Reply 2 Title"]) &&
             is_empty?(template["Quick Reply 3 Title"]) == true do
          {:error, "Quick Reply Button Titles are empty"}
        else
          true
        end

      _ ->
        {:error, "Invalid Button Type"}
    end
  end

  defp has_valid_buttons?(_has_buttons, _template), do: {:error, "Invalid Buttons"}

  @spec is_empty?(String.t()) :: boolean()
  defp is_empty?(button) do
    button
    |> String.trim()
    |> String.length()
    |> then(&(&1 == 0))
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
