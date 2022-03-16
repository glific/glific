defmodule Glific.Templates do
  @moduledoc """
  The Templates context.
  """
  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  use Tesla
  plug(Tesla.Middleware.FormUrlencoded)

  alias Glific.{
    Partners,
    Partners.Organization,
    Providers.Gupshup,
    Providers.GupshupEnterprise,
    Repo,
    Settings,
    Tags.Tag,
    Tags.TemplateTag,
    Templates.SessionTemplate
  }

  require Logger

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

      {:term, term}, query ->
        query
        |> join(:left, [template], template_tag in TemplateTag,
          as: :template_tag,
          on: template_tag.template_id == template.id
        )
        |> join(:left, [template_tag: template_tag], tag in Tag,
          as: :tag,
          on: template_tag.tag_id == tag.id
        )
        |> where(
          [template, tag: tag],
          ilike(template.label, ^"%#{term}%") or
            ilike(template.shortcode, ^"%#{term}%") or
            ilike(template.body, ^"%#{term}%") or
            ilike(tag.label, ^"%#{term}%") or
            ilike(tag.shortcode, ^"%#{term}%")
        )
        |> distinct([template], template.id)

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
         :ok <- validate_button_template(Map.merge(%{has_buttons: false}, attrs)) do
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

  defp validate_button_template(%{has_buttons: true, button_type: _, buttons: _} = _attrs),
    do: :ok

  defp validate_button_template(_) do
    {:error,
     [
       "Button Template",
       "for Button Templates has_buttons, button_type and buttons fields are required"
     ]}
  end

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
    organization = Partners.organization(attrs.organization_id)

    organization.bsp.shortcode
    |> case do
      "gupshup" -> Gupshup.Template.submit_for_approval(attrs)
      _ -> {:error, dgettext("errors", "Invalid BSP provider")}
    end
  end

  @spec import_templates(non_neg_integer(), String.t()) :: {:error, String.t()} | any()
  def import_templates(org_id, data) do
    organization = Partners.organization(org_id)

    organization.bsp.shortcode
    |> case do
      "gupshup_enterprise" -> GupshupEnterprise.Template.import_enterprise_templates(org_id, data)
      _ -> {:error, dgettext("errors", "Invalid BSP provider")}
    end
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
  @spec update_hsms(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsms(organization_id) do
    organization = Partners.organization(organization_id)

    organization.bsp.shortcode
    |> case do
      "gupshup" -> Gupshup.Template.update_hsm_templates(organization_id)
      _ -> {:error, dgettext("errors", "Invalid BSP provider")}
    end
  end

  @doc false
  @spec do_update_hsms(list(), Organization.t(), atom()) :: :ok
  def do_update_hsms(templates, organization, bsp \\ :gupshup) do
    languages =
      Settings.list_languages()
      |> Enum.map(fn language -> {language.locale, language.id} end)
      |> Map.new()

    db_templates = hsm_template_uuid_map(bsp)

    Enum.each(templates, fn template ->
      cond do
        !Map.has_key?(db_templates, get_template_key(template, bsp)) ->
          insert_hsm(template, organization, languages)

        # this check is required,
        # as is_active field can be updated by graphql API,
        # and should not be reverted back
        Map.has_key?(db_templates, get_template_key(template, bsp)) ->
          update_hsm(template, organization, languages, bsp)

        true ->
          true
      end
    end)
  end

  @spec get_template_key(map(), atom()) :: String.t()
  defp get_template_key(template, :gupshup), do: template["id"]
  defp get_template_key(template, :gupshup_enterprise), do: template["enterprise_id"]

  @spec update_hsm(map(), Organization.t(), map(), atom()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  defp update_hsm(template, organization, languages, bsp) do
    # get updated db templates to handle multiple approved translations
    db_templates = hsm_template_uuid_map(bsp)

    db_template_translations =
      db_templates
      |> Map.values()
      |> Enum.filter(fn db_template ->
        db_template.shortcode == template["elementName"] and
          is_existing_template?(db_template, template, bsp)
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

    do_update_hsm(template, db_templates, bsp)
  end

  @spec is_existing_template?(map(), map(), atom()) :: boolean()
  defp is_existing_template?(db_template, template, :gupshup),
    do: db_template.uuid != template["id"]

  defp is_existing_template?(db_template, template, :gupshup_enterprise),
    do: db_template.enterprise_template_id != template["enterprise_id"]

  @spec insert_hsm(map(), Organization.t(), map()) :: :ok
  defp insert_hsm(template, organization, languages) do
    example =
      case Jason.decode(template["meta"] || "{}") do
        {:ok, meta} ->
          meta["example"]

        _ ->
          nil
      end

    if example,
      do: do_insert_hsm(template, organization, languages, example),
      else: :ok
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
        enterprise_template_id: template["enterprise_id"] || ""
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

  @spec do_update_hsm(map(), map(), atom()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  defp do_update_hsm(template, db_templates, bsp) do
    current_template = db_templates[get_template_key(template, bsp)]
    update_attrs = %{status: template["status"]}

    update_attrs =
      if current_template.status != template["status"],
        do:
          Map.put(
            update_attrs,
            :is_active,
            template["status"] in ["APPROVED"]
          ),
        else: update_attrs

    {:ok, _} =
      db_templates[get_template_key(template, bsp)]
      |> SessionTemplate.changeset(update_attrs)
      |> Repo.update()
  end

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
      case Jason.decode(template["meta"]) do
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

  # A map where keys are hsm uuid and value will be template struct
  @spec hsm_template_uuid_map(atom()) :: map()
  defp hsm_template_uuid_map(:gupshup) do
    list_session_templates(%{filter: %{is_hsm: true}})
    |> Map.new(fn %{uuid: uuid} = template -> {uuid, template} end)
  end

  defp hsm_template_uuid_map(:gupshup_enterprise) do
    list_session_templates(%{filter: %{is_hsm: true}})
    |> Map.new(fn %{enterprise_template_id: enterprise_template_id} = template ->
      {enterprise_template_id, template}
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

  defp do_parse_buttons("QUICK_REPLY", button), do: button["text"]
end
