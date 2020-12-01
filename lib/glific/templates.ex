defmodule Glific.Templates do
  @moduledoc """
  The Templates context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
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
  def list_session_templates(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.list_filter(args, SessionTemplate, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of session_templates, using the same filter as list_session_templates
  """
  @spec count_session_templates(map()) :: integer
  def count_session_templates(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.count_filter(args, SessionTemplate, &filter_with/2)

  # codebeat:disable[ABC,LOC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:is_hsm, is_hsm}, query ->
        from q in query, where: q.is_hsm == ^is_hsm

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
  def create_session_template(attrs \\ %{}) do
    attrs = add_translation(attrs)
    %SessionTemplate{}
    |> SessionTemplate.changeset(attrs)
    |> Repo.insert()
  end

  defp add_translation(attrs) do
    if attrs |> Map.has_key?(:body) do
      translations = [
        %{
          "body" => attrs.body,
          "status" => "approved",
          "channel" => %{"uuid" => "", "name" => "WhatsApp"}
        }
      ]

      Map.put(attrs, :translations, translations)
    else
      attrs
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
    attrs = add_translation(attrs)
    session_template
    |> SessionTemplate.changeset(attrs)
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
end
