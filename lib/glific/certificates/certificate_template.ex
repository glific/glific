defmodule Glific.Certificates.CertificateTemplate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Enums.CertificateTemplateType,
    Partners.Organization,
    Repo
  }

  @slides_url_prefix "https://docs.google.com/presentation/"

  @required_fields [
    :label,
    :url,
    :organization_id
  ]

  @optional_fields [
    :description,
    :type
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          url: String.t() | nil,
          description: String.t() | nil,
          type: CertificateTemplateType,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "certificate_templates" do
    field :label, :string
    field :url, :string
    field :description, :string
    field :type, CertificateTemplateType
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(CertificateTemplate.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_poll, attrs) do
    wa_poll
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:label, min: 1, max: 40)
    |> validate_length(:description, min: 1, max: 150)
    |> validate_length(:url, min: 1)
    |> validate_url(attrs)
    |> unique_constraint([:label, :organization_id])
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Creates an certificate_template
  """
  @spec create_certificate_template(map()) ::
          {:ok, CertificateTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_certificate_template(attrs) do
    %CertificateTemplate{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get an certificate_template
  """
  @spec get_certificate_template(integer()) ::
          {:ok, CertificateTemplate.t()} | {:error, Ecto.Changeset.t()}
  def get_certificate_template(id),
    do: Repo.fetch_by(CertificateTemplate, %{id: id})

  @doc """
  Deletes certificate_template
  """
  @spec delete_certificate_template(CertificateTemplate.t()) ::
          {:ok, CertificateTemplate.t()} | {:error, Ecto.Changeset.t()}
  def delete_certificate_template(%CertificateTemplate{} = certificate_template) do
    Repo.delete(certificate_template)
  end

  @doc """
  Returns the list of certificate_templates.

  ## Examples

      iex> list_certificate_templates()
      [%CertificateTemplate{}, ...]

  """
  @spec list_certificate_templates(map()) :: [CertificateTemplate.t()]
  def list_certificate_templates(args) do
    args
    |> Repo.list_filter_query(
      CertificateTemplate,
      &Repo.opts_with_inserted_at/2,
      &Repo.filter_with/2
    )
    |> Repo.all()
  end

  @doc """
  Return the count of certificate_templates
  """
  @spec count_certificate_templates(map()) :: integer
  def count_certificate_templates(args),
    do: Repo.count_filter(args, CertificateTemplate, &Repo.filter_with/2)

  @doc """
  Updates a certificate_template.

  ## Examples

      iex> update_certificate_template(certificate_template, %{field: new_value})
      {:ok, %CertificateTemplate{}}

      iex> update_certificate_template(certificate_template, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_certificate_template(CertificateTemplate.t(), map()) ::
          {:ok, CertificateTemplate.t()} | {:error, Ecto.Changeset.t()}
  def update_certificate_template(%CertificateTemplate{} = certificate_template, attrs) do
    certificate_template
    |> CertificateTemplate.changeset(attrs)
    |> Repo.update()
  end

  @spec validate_url(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_url(%{changes: changes} = changeset, attrs) when not is_nil(changes.url) do
    url = changeset.changes[:url]
    type = attrs.type

    with :ok <- Glific.URI.cast(url),
         :ok <- validate_by_type(url, type) do
      changeset
    else
      {:error, _type, reason} ->
        add_error(
          changeset,
          :url,
          reason
        )

      _ ->
        add_error(
          changeset,
          :url,
          "Invalid Template url"
        )
    end
  end

  defp validate_url(changeset, _), do: changeset

  @spec validate_by_type(String.t(), atom()) :: :ok | {:error, atom(), String.t()}
  defp validate_by_type(url, :slides) do
    if String.starts_with?(url, @slides_url_prefix) do
      :ok
    else
      {:error, :slides, "Template url not a valid Google Slides"}
    end
  end
end
