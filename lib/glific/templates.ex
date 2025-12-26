defmodule Glific.Templates do
  @moduledoc """
  The Templates context.
  """
  import Ecto.Query, warn: false

  use Tesla
  plug(Tesla.Middleware.FormUrlencoded)

  alias Glific.{
    Communications.Mailer,
    Contacts.Contact,
    Mails.MailLog,
    Mails.ReportGupshupMail,
    Notifications,
    Partners,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Tags.Tag,
    Templates.SessionTemplate
  }

  require Logger

  @language_map %{
    "en" => 1,
    "en_GB" => 1,
    "en_US" => 1,
    "hi" => 2,
    "ta" => 3,
    "kn" => 4,
    "ml" => 5,
    "te" => 6,
    "gu" => 9,
    "bn" => 10,
    "pa" => 11,
    "mr" => 12,
    "ur" => 13,
    "es" => 14,
    "es_AR" => 14,
    "es_ES" => 14,
    "es_MX" => 14
  }

  @doc """
  Returns the list of session_templates.

  ## Examples

      iex> list_session_templates()
      [%SessionTemplate{}, ...]

  """
  @spec list_session_templates(map()) :: [SessionTemplate.t()]
  def list_session_templates(args),
    do: Repo.list_filter(args, SessionTemplate, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of session_templates, using the same filter as list_session_templates
  """
  @spec count_session_templates(map()) :: integer
  def count_session_templates(args),
    do: Repo.count_filter(args, SessionTemplate, &filter_with/2)

  # codebeat:disable[ABC,LOC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:is_hsm, is_hsm}, query ->
        from(q in query, where: q.is_hsm == ^is_hsm)

      {:is_active, is_active}, query ->
        from(q in query, where: q.is_active == ^is_active)

      {:status, status}, query ->
        from(q in query, where: q.status == ^status)

      {:category, category}, query ->
        from(q in query, where: q.category == ^category)

      {:language, language}, query ->
        from(q in query,
          join: l in assoc(q, :language),
          where: ilike(l.label, ^"%#{language}%")
        )

      {:tag_ids, tag_ids}, query ->
        from(q in query, where: q.tag_id in ^tag_ids)

      {:term, term}, query ->
        sub_query =
          Tag
          |> where([t], ilike(t.label, ^"%#{term}%"))
          |> select([t], t.id)

        query
        |> where([q], ilike(q.label, ^"%#{term}%") or q.tag_id in subquery(sub_query))
        |> or_where([q], ilike(q.shortcode, ^"%#{term}%"))
        |> or_where([q], ilike(q.body, ^"%#{term}%"))

      _, query ->
        query
    end)
  end

  # codebeat:enable[ABC,LOC]

  @doc """
  Gets a single session_template.

  Raises `Ecto.NoResultsError` if the SessionTemplate does not exist.

  ## Examples

      iex> get_session_template!(123)
      %SessionTemplate{}

      iex> get_session_template!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_session_template!(integer) :: SessionTemplate.t()
  def get_session_template!(id), do: Repo.get!(SessionTemplate, id)

  @doc """
  Creates a session_template.

  ## Examples

      iex> create_session_template(%{field: value})
      {:ok, %SessionTemplate{}}

      iex> create_session_template(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_session_template(map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_session_template(%{is_hsm: true} = attrs) do
    # validate HSM before calling the BSP's API
    attrs =
      if Map.has_key?(attrs, :shortcode),
        do: Map.merge(attrs, %{shortcode: String.downcase(attrs.shortcode)}),
        else: attrs

    with :ok <- validate_hsm(attrs),
         :ok <- validate_button_template(Map.merge(%{has_buttons: false}, attrs)),
         :ok <- validate_template_length(attrs) do
      submit_for_approval(attrs)
    end
  end

  def create_session_template(attrs),
    do: do_create_session_template(attrs)

  @spec validate_hsm(map()) :: :ok | {:error, [String.t()]}
  defp validate_hsm(%{shortcode: shortcode, category: _, example: _} = _attrs) do
    if String.match?(shortcode, ~r/^[a-z0-9_]*$/),
      do: :ok,
      else: {:error, ["shortcode", "only '_' and alphanumeric characters are allowed"]}
  end

  defp validate_hsm(_) do
    {:error,
     ["HSM approval", "for HSM approval shortcode, category and example fields are required"]}
  end

  @spec validate_button_template(map()) :: :ok | {:error, [String.t()]}
  defp validate_button_template(%{has_buttons: false} = _attrs), do: :ok

  defp validate_button_template(%{has_buttons: true, button_type: _, buttons: buttons} = _attrs) do
    invalid_texts =
      Enum.filter(buttons, fn %{"text" => text} ->
        contains_invalid_chars?(text)
      end)

    if invalid_texts == [],
      do: :ok,
      else:
        {:error,
         [
           "Button Template",
           "Button texts cannot contain any variables, newlines, emojis or formatting characters (e.g., bold, italics)."
         ]}
  end

  defp validate_button_template(_) do
    {:error,
     [
       "Button Template",
       "for Button Templates has_buttons, button_type and buttons fields are required"
     ]}
  end

  @spec contains_invalid_chars?(String.t()) :: boolean()
  defp contains_invalid_chars?(text) do
    contains_variable?(text) or
      contains_newline?(text) or
      contains_formatting?(text) or
      contains_emoji?(text)
  end

  @spec contains_variable?(String.t()) :: boolean()
  defp contains_variable?(text) do
    Regex.match?(~r/\{\{.*?\}\}/, text)
  end

  @spec contains_newline?(String.t()) :: boolean()
  defp contains_newline?(text) do
    String.contains?(text, "\n")
  end

  @spec contains_emoji?(String.t()) :: boolean()
  defp contains_emoji?(text) do
    emoji_regex =
      ~r/[\x{1F600}-\x{1F64F}|\x{1F300}-\x{1F5FF}|\x{1F680}-\x{1F6FF}|\x{1F700}-\x{1F77F}|\x{1F780}-\x{1F7FF}|\x{1F800}-\x{1F8FF}|\x{1F900}-\x{1F9FF}|\x{1FA00}-\x{1FA6F}|\x{1FA70}-\x{1FAFF}|\x{2600}-\x{26FF}|\x{2700}-\x{27BF}|\x{1F1E6}-\x{1F1FF}]/u

    Regex.match?(emoji_regex, text)
  end

  @spec contains_formatting?(String.t()) :: boolean()
  defp contains_formatting?(text) do
    # assuming bold, italics, and strikethrough are represented by *, _, ~
    Regex.match?(~r/[*_~]/, text)
  end

  @spec validate_template_length(map()) :: :ok | {:error, [String.t()]}
  defp validate_template_length(%{body: body} = attrs) do
    buttons = Map.get(attrs, :buttons, [])
    footer = Map.get(attrs, :footer, "")

    total_length =
      String.length(body || "") +
        calculate_buttons_length(buttons) +
        String.length(footer)

    cond do
      Enum.any?(buttons, fn %{"text" => text} -> String.length(text || "") > 20 end) ->
        {:error, ["Button Validation", "Buttons text cannot be greater than 20"]}

      String.length(footer) > 60 ->
        {:error, ["Footer Validation", "Footer text cannot be greater than 60 characters"]}

      total_length <= 1024 ->
        :ok

      true ->
        {:error, ["Character Limit", "Exceeding character limit"]}
    end
  end

  defp calculate_buttons_length(buttons) when is_list(buttons) do
    Enum.reduce(buttons, 0, fn %{"text" => text}, acc ->
      acc + String.length(text || "")
    end)
  end

  defp calculate_buttons_length(nil), do: 0

  @doc false
  @spec do_create_session_template(map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  def do_create_session_template(attrs) do
    %SessionTemplate{}
    |> SessionTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, String.t()}
  defp submit_for_approval(attrs) do
    Logger.info("Submitting template for approval with attrs as #{inspect(attrs)}")
    bsp_module = Provider.bsp_module(attrs.organization_id, :template)
    bsp_module.submit_for_approval(attrs)
  end

  @doc """
  Imports pre approved templates from bsp
  """
  @spec import_templates(non_neg_integer(), String.t()) :: {:ok, any} | {:error, any}
  def import_templates(org_id, data) do
    Provider.bsp_module(org_id, :template).import_templates(org_id, data)
  end

  @doc """
  Bulk applying templates from CSV
  """
  @spec bulk_apply_templates(non_neg_integer(), String.t()) :: {:ok, any} | {:error, any}
  def bulk_apply_templates(org_id, data) do
    Provider.bsp_module(org_id, :template).bulk_apply_templates(org_id, data)
  end

  @doc """
  Updates a session_template.

  ## Examples

      iex> update_session_template(session_template, %{field: new_value})
      {:ok, %SessionTemplate{}}

      iex> update_session_template(session_template, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_session_template(SessionTemplate.t(), map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  def update_session_template(%SessionTemplate{} = session_template, attrs) do
    session_template
    |> SessionTemplate.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Editing pre approved templates
  """
  @spec edit_approved_template(integer(), map()) :: {:ok, any} | {:error, any}
  def edit_approved_template(template_id, params) do
    Provider.bsp_module(params.organization_id, :template).edit_approved_template(
      template_id,
      params
    )
  end

  @doc """
  Deletes a session_template.

  ## Examples

      iex> delete_session_template(session_template)
      {:ok, %SessionTemplate{}}

      iex> delete_session_template(session_template)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_session_template(SessionTemplate.t()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  def delete_session_template(%SessionTemplate{} = session_template) do
    if session_template.is_hsm do
      Task.Supervisor.async_nolink(Glific.TaskSupervisor, fn ->
        org_id = session_template.organization_id
        bsp_module = Provider.bsp_module(org_id, :template)
        bsp_module.delete(org_id, Map.from_struct(session_template))
      end)
    end

    Repo.delete(session_template)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session_template changes.

  ## Examples

      iex> change_session_template(session_template)
      %Ecto.Changeset{data: %SessionTemplate{}}

  """
  @spec change_session_template(SessionTemplate.t(), map()) :: Ecto.Changeset.t()
  def change_session_template(%SessionTemplate{} = session_template, attrs \\ %{}) do
    SessionTemplate.changeset(session_template, attrs)
  end

  @doc """
  Create a session template form message
  Body and type will be the message attributes
  """
  @spec create_template_from_message(%{message_id: integer, input: map}) ::
          {:ok, SessionTemplate.t()} | {:error, String.t()}
  def create_template_from_message(%{message_id: message_id, input: input}) do
    message =
      Glific.Messages.get_message!(message_id)
      |> Repo.preload([:contact])

    Map.merge(
      %{body: message.body, type: message.type, organization_id: message.organization_id},
      input
    )
    |> create_session_template()
  end

  @doc """
  get and update list of hsm of an organization
  """
  @spec sync_hsms_from_bsp(non_neg_integer()) :: :ok | {:error, String.t()}
  def sync_hsms_from_bsp(organization_id) do
    bsp_module = Provider.bsp_module(organization_id, :template)
    res = bsp_module.update_hsm_templates(organization_id)

    Logger.info(
      "Templates has been sync for org id: #{organization_id} with response: #{inspect(res)}"
    )

    res
  end

  @doc false
  @spec update_hsms(list(), Organization.t()) :: :ok
  def update_hsms(templates, organization) do
    db_templates = hsm_template_uuid_map()

    Enum.each(templates, fn template ->
      cond do
        !Map.has_key?(db_templates, template["bsp_id"]) ->
          db_templates
          |> existing_template?(template, organization)
          |> upsert_hsm(template, organization)

        # this check is required,
        # as is_active field can be updated by graphql API,
        # and should not be reverted back
        Map.has_key?(db_templates, template["bsp_id"]) ->
          update_hsm(template, organization, @language_map)

        true ->
          true
      end
    end)
  end

  @spec existing_template?(map(), map(), Organization.t()) :: boolean()
  defp existing_template?(db_templates, template, organization) do
    Enum.any?(db_templates, fn {_bsp_id, db_template} ->
      element_name = template["elementName"]
      language_code = template["languageCode"]

      language_id = Map.get(@language_map, language_code, organization.default_language_id)

      db_template.shortcode == element_name && db_template.language_id == language_id
    end)
  end

  @spec upsert_hsm(boolean(), map(), Organization.t()) :: :ok
  defp upsert_hsm(false, template, organization) do
    example =
      case Jason.decode(template["meta"] || "{}") do
        {:ok, meta} ->
          meta["example"] || "NA"

        _ ->
          "NA"
      end

    if example,
      do: do_insert_hsm(template, organization, @language_map, example),
      else: :ok
  end

  defp upsert_hsm(true, template, organization) do
    language_id =
      Map.get(@language_map, template["languageCode"], organization.default_language_id)

    {:ok, session_template} =
      SessionTemplate
      |> Repo.fetch_by(%{language_id: language_id, shortcode: template["elementName"]})

    session_template
    |> SessionTemplate.changeset(%{uuid: template["bsp_id"]})
    |> Repo.update()

    :ok
  end

  @spec update_hsm(map(), Organization.t(), map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  defp update_hsm(template, organization, languages) do
    # get updated db templates to handle multiple approved translations
    db_templates = hsm_template_uuid_map()

    db_template_translations =
      db_templates
      |> Map.values()
      |> Enum.filter(fn db_template ->
        db_template.shortcode == template["elementName"] and
          db_template.bsp_id != template["bsp_id"]
      end)

    approved_db_templates =
      db_template_translations
      |> Enum.filter(fn db_template -> db_template.status == "APPROVED" end)

    with true <- template["status"] == "APPROVED",
         true <- length(db_template_translations) >= 1,
         true <- length(approved_db_templates) >= 1 do
      approved_db_templates
      |> Enum.each(fn approved_db_template ->
        update_hsm_translation(template, approved_db_template, organization, languages)
      end)
    end

    do_update_hsm(template, db_templates)
  end

  @spec do_insert_hsm(map(), Organization.t(), map(), String.t()) :: :ok
  defp do_insert_hsm(template, organization, languages, example) do
    number_of_parameter = length(Regex.split(~r/{{.}}/, template["data"])) - 1

    type =
      template["templateType"]
      |> String.downcase()
      |> Glific.safe_string_to_atom()

    # setting default language id if languageCode is not known
    language_id = languages[template["languageCode"]] || organization.default_language_id

    Logger.info("Language id for template #{template["elementName"]}
      org_id: #{organization.id} has been updated as #{language_id}")

    is_active =
      if template["status"] in ["APPROVED", "SANDBOX_REQUESTED"],
        do: true,
        else: false

    attrs =
      %{
        uuid: template["id"],
        body: template["data"],
        shortcode: template["elementName"],
        label: template["elementName"],
        category: template["category"],
        example: example,
        type: type,
        language_id: language_id,
        organization_id: organization.id,
        is_hsm: true,
        status: template["status"],
        is_active: is_active,
        number_parameters: number_of_parameter,
        bsp_id: template["bsp_id"] || template["id"],
        buttonType: template["buttonSupported"],
        containerMeta: template["containerMeta"]
      }
      |> check_for_button_template()

    %SessionTemplate{}
    |> SessionTemplate.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, template} ->
        Logger.info("New Session Template Added with label: #{template.label}")

      {:error, error} ->
        Logger.error(
          "Error adding new Session Template: #{inspect(error)} and attrs #{inspect(attrs)}"
        )
    end

    :ok
  end

  @spec check_for_button_template(map()) :: map()
  defp check_for_button_template(%{buttonType: "FLOW"} = template) do
    case extract_flow_buttons(template) do
      {:ok, buttons} ->
        template
        |> Map.put(:has_buttons, true)
        |> Map.put(:button_type, :whatsapp_form)
        |> Map.put(:buttons, buttons)

      {:error, reason} ->
        Logger.error("FLOW button extraction failed: #{reason}")
        template
    end
  end

  defp check_for_button_template(%{body: template_body} = template) do
    [body | buttons] = template_body |> String.split(["| ["])

    if body == template_body do
      template
    else
      template
      |> Map.put(:body, body)
      |> Map.put(:has_buttons, true)
      |> update_template_buttons(buttons)
    end
  end

  @spec extract_flow_buttons(map()) :: {:ok, list()} | {:error, String.t()}
  defp extract_flow_buttons(%{containerMeta: container_meta}) when is_binary(container_meta) do
    case Jason.decode(container_meta) do
      {:ok, %{"buttons" => buttons}} when is_list(buttons) ->
        {:ok, buttons}

      {:ok, _decoded} ->
        {:error, "No buttons found in containerMeta"}

      {:error, reason} ->
        {:error, "Failed to decode containerMeta: #{inspect(reason)}"}
    end
  end

  defp extract_flow_buttons(_template) do
    {:error, "No containerMeta found"}
  end

  @spec update_template_buttons(map(), list()) :: map()
  defp update_template_buttons(template, buttons) do
    parsed_buttons =
      buttons
      |> Enum.map(fn button ->
        button_list = String.replace(button, "]", "") |> String.split(",")
        parse_template_button(button_list, length(button_list))
      end)

    button_type =
      if parsed_buttons |> Enum.any?(fn %{type: button_type} -> button_type == "QUICK_REPLY" end),
        do: :quick_reply,
        else: :call_to_action

    template
    |> Map.put(:buttons, parsed_buttons)
    |> Map.put(:button_type, button_type)
  end

  @spec parse_template_button(list(), non_neg_integer()) :: map()
  defp parse_template_button([text, content], 2) do
    if String.contains?(content, "http"),
      do: %{url: content, text: text, type: "URL"},
      else: %{phone_number: content, text: text, type: "PHONE_NUMBER"}
  end

  defp parse_template_button([content], 1), do: %{text: content, type: "QUICK_REPLY"}

  @spec do_update_hsm(map(), map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}

  defp do_update_hsm(template, db_templates) do
    current_template = db_templates[template["bsp_id"]]

    update_attrs =
      if current_template.status != template["status"] do
        change_template_status(template["status"], current_template, template)
        |> Map.put(:category, template["category"])
        |> Map.put(:quality, template["quality"])
      else
        %{
          status: template["status"],
          category: template["category"],
          quality: template["quality"]
        }
      end

    update_attrs =
      if current_template.uuid,
        do: Map.put(update_attrs, :uuid, current_template.uuid),
        else: Map.put(update_attrs, :uuid, template["id"])

    db_templates[template["bsp_id"]]
    |> SessionTemplate.changeset(update_attrs)
    |> Repo.update()
  end

  @spec change_template_status(String.t(), map(), map()) :: map()
  defp change_template_status("APPROVED", db_template, _bsp_template) do
    Notifications.create_notification(%{
      category: "Templates",
      message: "Template #{db_template.shortcode} has been approved",
      severity: Notifications.types().info,
      organization_id: db_template.organization_id,
      entity: %{
        id: db_template.id,
        shortcode: db_template.shortcode,
        label: db_template.label,
        uuid: db_template.uuid
      }
    })

    %{status: "APPROVED", is_active: true}
  end

  defp change_template_status("REJECTED", db_template, bsp_template) do
    Notifications.create_notification(%{
      category: "Templates",
      message: "Template #{db_template.shortcode} has been rejected",
      severity: Notifications.types().info,
      organization_id: db_template.organization_id,
      entity: %{
        id: db_template.id,
        shortcode: db_template.shortcode,
        label: db_template.label,
        uuid: db_template.uuid
      }
    })

    %{status: "REJECTED", reason: bsp_template["reason"]}
  end

  defp change_template_status("FAILED", db_template, bsp_template) do
    Notifications.create_notification(%{
      category: "Templates",
      message: "Template #{db_template.shortcode} has been failed",
      severity: Notifications.types().info,
      organization_id: db_template.organization_id,
      entity: %{
        id: db_template.id,
        shortcode: db_template.shortcode,
        label: db_template.label,
        uuid: db_template.uuid
      }
    })

    %{status: "FAILED", reason: bsp_template["reason"]}
  end

  defp change_template_status(status, _db_template, _bsp_template), do: %{status: status}

  @spec update_hsm_translation(map(), SessionTemplate.t(), Organization.t(), map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  defp update_hsm_translation(template, approved_db_template, organization, languages) do
    number_of_parameter = template_parameters_count(%{body: template["data"]})

    type =
      template["templateType"]
      |> String.downcase()
      |> Glific.safe_string_to_atom()

    # setting default language id if languageCode is not known
    language_id = languages[template["languageCode"]] || organization.default_language_id

    example =
      case Jason.decode(template["meta"] || "{}") do
        {:ok, meta} ->
          meta["example"]

        _ ->
          nil
      end

    translation = %{
      "#{language_id}" => %{
        uuid: template["id"],
        body: template["data"],
        language_id: language_id,
        status: template["status"],
        type: type,
        number_parameters: number_of_parameter,
        example: example,
        category: template["category"],
        label: template["elementName"]
      }
    }

    translations = Map.merge(approved_db_template.translations, translation)

    update_attrs = %{
      translations: translations
    }

    approved_db_template
    |> SessionTemplate.changeset(update_attrs)
    |> Repo.update()
  end

  @doc """
  Returns the count of variables in template
  """
  @spec template_parameters_count(map()) :: non_neg_integer()
  def template_parameters_count(template) do
    template = parse_buttons(template, false, Map.get(template, :has_buttons, false))

    template.body
    |> String.split()
    |> Enum.reduce([], fn word, acc ->
      with true <- String.match?(word, ~r/{{([1-9]|[1-9][0-9])}}/),
           clean_word <- Glific.string_clean(word) do
        acc ++ [clean_word]
      else
        _ -> acc
      end
    end)
    |> Enum.uniq()
    |> Enum.count()
  end

  @spec hsm_template_uuid_map() :: map()
  defp hsm_template_uuid_map do
    list_session_templates(%{filter: %{is_hsm: true}})
    |> Map.new(fn %{bsp_id: bsp_id} = template ->
      {bsp_id, template}
    end)
  end

  @doc false
  @spec parse_buttons(map(), boolean(), boolean()) :: map()
  def parse_buttons(session_template, false, true) do
    # parsing buttons only when template is not already translated, else buttons are part of body
    updated_body =
      session_template.buttons
      |> Enum.reduce(session_template.body, fn button, acc ->
        "#{acc}| [" <> do_parse_buttons(button["type"], button) <> "] "
      end)

    session_template
    |> Map.merge(%{body: updated_body})
  end

  def parse_buttons(session_template, _is_translated, _has_buttons), do: session_template

  @spec do_parse_buttons(String.t(), map()) :: String.t()
  defp do_parse_buttons("URL", button), do: button["text"] <> ", " <> button["url"]

  defp do_parse_buttons("PHONE_NUMBER", button),
    do: button["text"] <> ", " <> button["phone_number"]

  defp do_parse_buttons(type, button) when type in ["QUICK_REPLY", "OTP", "FLOW"],
    do: button["text"]

  @doc """
  List of available categories provided by whatsapp
  """
  @spec list_whatsapp_hsm_categories() :: [String.t()]
  def list_whatsapp_hsm_categories do
    [
      "UTILITY",
      "MARKETING"
    ]
  end

  @doc """
  Report mail to gupshup
  """
  @spec report_to_gupshup(non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, any} | {:error, any}
  def report_to_gupshup(org_id, template_id, cc \\ %{}) do
    org = Partners.organization(org_id)

    # getting the email values only
    cc = Map.values(cc)

    phone =
      Contact
      |> where([c], c.id == ^org.contact_id)
      |> select([c], c.phone)
      |> Repo.one()

    app_id = Map.get(org.services["gupshup"].secrets, "app_id")
    app_name = Map.get(org.services["gupshup"].secrets, "app_name")

    bsp_id =
      SessionTemplate
      |> where([st], st.id == ^template_id)
      |> select([st], st.bsp_id)
      |> Repo.one()

    opts = [
      phone: phone,
      bsp_id: bsp_id,
      cc: cc
    ]

    time = Glific.go_back_time(24)
    ## We need to check if we have already sent this notification in last go_back time
    if MailLog.mail_sent_in_past_time?("report_gupshup", time, org.id) do
      {:error, "Already a template has been raised to Gupshup in last 24hrs"}
    else
      raise_to_gupshup(org, app_id, app_name, opts)
    end
  end

  @spec raise_to_gupshup(Organization.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any()} | {:error, any()}
  defp raise_to_gupshup(org, app_id, app_name, opts) do
    case ReportGupshupMail.raise_to_gupshup(org, app_id, app_name, opts)
         |> Mailer.send(%{
           category: "report_gupshup",
           organization_id: org.id
         }) do
      {:ok, %{id: _id}} -> {:ok, %{message: "Successfully sent mail to Gupshup Support"}}
      error -> {:ok, %{message: error}}
    end
  end

  @doc """
  get template from EEx based on variables
  """
  @spec template(integer(), [String.t()]) :: binary
  def template(template_uuid, variables \\ []) do
    %{
      uuid: template_uuid,
      name: "Template",
      variables: variables,
      expression: nil
    }
    |> Jason.encode!()
  end
end
