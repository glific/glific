defmodule Glific.Extensions.Extension do
  @moduledoc """
  The table structure for all our extensions
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  # define all the required fields for
  @required_fields [
    :name,
    :code,
    :organization_id
  ]

  # define all the optional fields for organization
  @optional_fields [
    :module,
    :is_active,
    :is_valid
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          code: String.t() | nil,
          module: String.t() | nil,
          is_valid: boolean | false,
          is_active: boolean() | true,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "extensions" do
    field :name, :string
    field :code, :string
    field :module, :string

    field :is_valid, :boolean, default: false
    field :is_active, :boolean, default: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Extension.t(), map()) :: Ecto.Changeset.t()
  def changeset(extension, attrs) do
    extension
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:module, :name, :organization_id])
  end

  @spec compile(map(), String.t(), String.t() | nil) :: map()
  defp compile(attrs, code, module \\ nil)

  defp compile(%{is_active: true}, code, module) do
    # unload the previous loaded module if it exists
    # typically in an update
    unload(module)

    case do_compile(code) do
      {:ok, module} ->
        %{
          is_valid: true,
          module: module
        }

      {:error, _} ->
        %{
          is_valid: false,
          module: nil
        }
    end
  end

  defp compile(_, _code, module) do
    # incase of is_active as false we do not compile the code
    unload(module)

    %{
      is_valid: false,
      module: nil
    }
  end

  @spec do_compile(String.t()) :: {:ok | :error, String.t()}
  defp do_compile(code) do
    results = Code.compile_string(code)
    Code.purge_compiler_modules()

    if length(results) == 1 do
      {module, _binary} = hd(results)
      {:ok, Atom.to_string(module)}
    else
      {:error, "Error in compiling file"}
    end
  rescue
    e ->
      {:error, "Error in compiling file, #{inspect(e)}"}
  end

  @spec unload(String.t() | nil) :: :ok
  defp unload(nil), do: :ok

  defp unload(module) do
    module = module |> String.to_existing_atom()
    module |> :code.purge()
    module |> :code.delete()
  end

  @doc """
  Create a extension record
  """
  @spec create_extension(map()) :: {:ok, Extension.t()} | {:error, Ecto.Changeset.t()}
  def create_extension(attrs) do
    attrs = Map.merge(attrs, compile(%{is_active: attrs.is_active}, attrs.code))

    %Extension{}
    |> Extension.changeset(Map.put(attrs, :organization_id, attrs.organization_id))
    |> Repo.insert()
  end

  @doc """
  Retrieve a extension record by clauses
  """
  @spec get_extension(map()) :: Extension.t() | nil
  def get_extension(clauses), do: Repo.get_by(Extension, clauses, skip_organization_id: true)

  @doc """
  Update the extension record
  """
  @spec update_extension(Extension.t(), map()) ::
          {:ok, Extension.t()} | {:error, Ecto.Changeset.t()}
  def update_extension(%Extension{} = extension, attrs) do
    attrs = Map.merge(attrs, compile(%{is_active: attrs.is_active}, attrs.code, extension.module))

    extension
    |> Extension.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete the extension record
  """
  @spec delete_extension(Extension.t()) ::
          {:ok, Extension.t()} | {:error, Ecto.Changeset.t()}
  def delete_extension(%Extension{} = extension) do
    Repo.delete(extension, skip_organization_id: true)
  end
end
