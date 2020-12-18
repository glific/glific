defmodule Glific.Templates do
  @moduledoc """
  The Templates context.
  """
  import Ecto.Query, warn: false

  use Tesla
  plug Tesla.Middleware.FormUrlencoded

  alias Glific.{
    Partners,
    Partners.Organization,
    Repo,
    Tags.Tag,
    Tags.TemplateTag,
    Templates.SessionTemplate
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
        from q in query, where: q.is_hsm == ^is_hsm

      {:is_active, is_active}, query ->
        from q in query, where: q.is_active == ^is_active

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
    submit_for_approval(attrs)
  end

  def create_session_template(attrs) do
    do_create_session_template(attrs)
  end

  @spec do_create_session_template(map()) ::
          {:ok, SessionTemplate.t()} | {:error, Ecto.Changeset.t()}
  defp do_create_session_template(attrs) do
    %SessionTemplate{}
    |> SessionTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, String.t()}
  defp submit_for_approval(%{shortcode: _, category: _, example: _} = attrs) do
    organization = Partners.organization(attrs.organization_id)

    bsp_creds = organization.services["bsp"]
    api_key = bsp_creds.secrets["api_key"]
    url = bsp_creds.keys["api_end_point"] <> "/template/add/" <> bsp_creds.secrets["app_name"]

    with {:ok, response} <- post(url, body(attrs, organization), headers: [{"apikey", api_key}]),
         {200, _response} <- {response.status, response} do
      {:ok, response_data} = Jason.decode(response.body)

      attrs
      |> Map.merge(%{
        uuid: response_data["template"]["id"],
        status: response_data["template"]["status"]
      })
      |> do_create_session_template()
    else
      {status, response} ->
        # structure of response body can be different for different errors
        {:error, ["BSP response status: #{to_string(status)}", response.body]}

      _ ->
        {:error, ["BSP", "couldn't submit for approval"]}
    end
  end

  defp submit_for_approval(_) do
    {:error,
     ["HSM approval", "for HSM approval shortcode, category and example fields are required"]}
  end

  @spec body(map(), Organization.t()) :: map()
  defp body(attrs, organization) do
    language =
      Enum.find(organization.languages, fn language ->
        to_string(language.id) == attrs.language_id
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

    bsp_creds = organization.services["bsp"]
    api_key = bsp_creds.secrets["api_key"]
    url = bsp_creds.keys["api_end_point"] <> "/template/list/" <> bsp_creds.secrets["app_name"]

    with {:ok, response} <-
           Tesla.get(url, headers: [{"apikey", api_key}]),
         {:ok, response_data} <- Jason.decode(response.body),
         false <- is_nil(response_data["templates"]) do
      do_update_hsms(response_data["templates"], organization)

      :ok
    else
      _ ->
        {:error, ["BSP", "couldn't connect"]}
    end
  end

  @spec do_update_hsms(map(), Organization.t()) :: :ok
  defp do_update_hsms(templates, organization) do
    organization_languages =
      Enum.map(organization.languages, fn language -> {language.locale, language.id} end)
      |> Map.new()

    db_templates =
      list_session_templates(%{filter: %{is_hsm: true}})
      |> Map.new(fn %{uuid: uuid} = template -> {uuid, template} end)

    Enum.each(templates, fn template ->
      cond do
        !Map.has_key?(db_templates, template["id"]) ->
          insert_hsm(template, organization, organization_languages)

        # this check is required,
        # as is_active field can be updated by graphql API,
        # and should not be reverted back
        template["modifiedOn"] >
            DateTime.to_unix(db_templates[template["id"]].updated_at, :millisecond) ->
          update_hsm(template, db_templates)

        true ->
          true
      end
    end)
  end

  @spec insert_hsm(map(), Organization.t(), map()) :: {:ok, SessionTemplate.t()}
  defp insert_hsm(template, organization, organization_languages) do
    number_of_parameter = length(Regex.split(~r/{{.}}/, template["data"])) - 1

    type =
      template["templateType"]
      |> String.downcase()
      |> String.to_existing_atom()

    # setting default language id if languageCode is not known
    language_id =
      organization_languages[template["languageCode"]] || organization.default_language_id

    is_active =
      if template["status"] in ["APPROVED", "SANDBOX_REQUESTED"],
        do: true,
        else: false

    attrs = %{
      uuid: template["id"],
      body: template["data"],
      shortcode: template["elementName"],
      label: template["elementName"],
      type: type,
      language_id: language_id,
      organization_id: organization.id,
      is_hsm: true,
      status: template["status"],
      is_active: is_active,
      number_parameters: number_of_parameter
    }

    {:ok, _} =
      %SessionTemplate{}
      |> SessionTemplate.changeset(attrs)
      |> Repo.insert()
  end

  @spec update_hsm(map(), map()) :: {:ok, SessionTemplate.t()}
  defp update_hsm(template, db_templates) do
    update_attrs = %{
      status: template["status"],
      is_active:
        if(template["status"] in ["APPROVED", "SANDBOX_REQUESTED"],
          do: true,
          else: false
        )
    }

    {:ok, _} =
      db_templates[template["id"]]
      |> SessionTemplate.changeset(update_attrs)
      |> Repo.update()
  end
end
