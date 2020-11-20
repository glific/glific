defmodule Glific.Extensions do
  @moduledoc """
  The Extensions Context, which encapsulates and manages dynamic loading and unloading of elixir code
  """

  alias Glific.{Extensions.Extension, Repo}

  # import Ecto.Query

  @doc """
  Returns the list of extensions.

  ## Examples

      iex> list_extensions()
      [%Extension{}, ...]

  """
  @spec list_extensions(map()) :: [Extension.t()]
  def list_extensions(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.list_filter(args, Extension, &Repo.opts_with_name/2, &Repo.filter_with/2)

  @doc """
  Return the count of extensions, using the same filter as list_extensions
  """
  @spec count_extensions(map()) :: integer
  def count_extensions(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.count_filter(args, Extension, &Repo.filter_with/2)

  @doc """
  Gets a single extension.

  Raises `Ecto.NoResultsError` if the Extension does not exist.

  ## Examples

      iex> get_extension!(123)
      %Extension{}

      iex> get_extension!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_extension!(integer) :: Extension.t()
  def get_extension!(id), do: Repo.get!(Extension, id)

  @doc """
  Creates a extension.

  ## Examples

      iex> create_extension(%{field: value})
      {:ok, %Extension{}}

      iex> create_extension(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_extension(map()) :: {:ok, Extension.t()} | {:error, Ecto.Changeset.t()}
  def create_extension(attrs) do
    %Extension{}
    |> Extension.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a extension.

  ## Examples

      iex> update_extension(extension, %{field: new_value})
      {:ok, %Extension{}}

      iex> update_extension(extension, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_extension(Extension.t(), map()) ::
          {:ok, Extension.t()} | {:error, Ecto.Changeset.t()}
  def update_extension(%Extension{} = extension, attrs) do
    extension
    |> Extension.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a extension.

  ## Examples

      iex> delete_extension(extension)
      {:ok, %Extension{}}

      iex> delete_extension(extension)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_extension(Extension.t()) :: {:ok, Extension.t()} | {:error, Ecto.Changeset.t()}
  def delete_extension(%Extension{} = extension) do
    extension
    |> Extension.changeset(%{})
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking extension changes.

  ## Examples

      iex> change_extension(extension)
      %Ecto.Changeset{data: %Extension{}}

  """
  @spec change_extension(Extension.t(), map()) :: Ecto.Changeset.t()
  def change_extension(%Extension{} = extension, attrs \\ %{}) do
    Extension.changeset(extension, attrs)
  end

  @doc """
  Given an extension name. It first requires the file and if that succeeds, it then
  calls the function in the specified module and returns the json result
  """
  @spec execute(String.t() | Extension.t(), map()) :: map()
  def execute(name, body) when is_binary(name) do
    case Repo.fetch_by(Extension, %{name: name}) do
      {:ok, extension} -> execute(extension, body)
      _ -> raise "Could not find extension with name #{name}"
    end
  end

  def execute(extension, body) do
    module = String.to_existing_atom("Elixir." <> extension.module)

    condition =
      if is_nil(extension.condition) or extension.condition == "",
        do: true,
        else: apply(module, String.to_existing_atom(extension.condition), extension.args)

    if condition,
      do: apply(module, String.to_existing_atom(extension.action), [body | extension.args]),
      else: %{}
  end
end
