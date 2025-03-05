defmodule Glific.Certificates.IssuedCertificate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Repo
  alias Glific.Certificates.IssuedCertificate

  alias Glific.{
    Certificates.CertificateTemplate,
    Contacts.Contact,
    Partners.Organization
  }

  @required_fields [
    :certificate_template_id,
    :contact_id,
    :organization_id
  ]

  @optional_fields [
    :gcs_url,
    :errors,
    :status
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          certificate_template_id: non_neg_integer() | nil,
          certificate_template: CertificateTemplate.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          gcs_url: String.t() | nil,
          errors: map() | nil,
          status: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "issued_certificates" do
    field :gcs_url, :string
    field :errors, :map
    field :status, :string
    belongs_to :certificate_template, CertificateTemplate
    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(IssuedCertificate.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_poll, attrs) do
    wa_poll
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:certificate_template_id)
  end

  @doc """
  Creates an certificate_template
  """
  @spec create_issued_certificate(map()) ::
          {:ok, IssuedCertificate.t()} | {:error, Ecto.Changeset.t()}
  def create_issued_certificate(attrs) do
    %IssuedCertificate{}
    |> changeset(attrs)
    |> Repo.insert()
  end
end
