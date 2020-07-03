defmodule Glific.Settings do
  @moduledoc """
  The Settings context. This includes language for now.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo
  alias Glific.Settings.Language

  @doc """
  Returns the list of languages.

  ## Examples

      iex> list_languages()
      [%Language{}, ...]

  """
  @spec list_languages(map()) :: [Language.t(), ...]
  def list_languages(args \\ %{}) do
    args
    |> Enum.reduce(Language, fn
      {:label, label}, query ->
        from q in query,
          where: ilike(q.label, ^"%#{label}%") or ilike(q.label_locale, ^"%#{label}%")

      {:locale, locale}, query ->
        from q in query, where: ilike(q.locale, ^"%#{locale}%")
    end)
    |> Repo.all()
  end

  @doc """
  Return the count of languages, using the same filter as list_languages
  """
  @spec count_languages(map()) :: integer
  def count_languages(_args \\ %{}) do
    Language
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single language.

  Raises `Ecto.NoResultsError` if the Language does not exist.

  ## Examples

      iex> get_language!(123)
      %Language{}

      iex> get_language!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_language!(integer) :: Language.t()
  def get_language!(id), do: Repo.get!(Language, id)

  @doc """
  Creates a language.

  ## Examples

      iex> create_language(%{field: value})
      {:ok, %Language{}}

      iex> create_language(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_language(map()) :: {:ok, Language.t()} | {:error, Ecto.Changeset.t()}
  def create_language(attrs \\ %{}) do
    %Language{}
    |> Language.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a language.

  ## Examples

      iex> update_language(language, %{field: new_value})
      {:ok, %Language{}}

      iex> update_language(language, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_language(Language.t(), map()) :: {:ok, Language.t()} | {:error, Ecto.Changeset.t()}
  def update_language(%Language{} = language, attrs) do
    language
    |> Language.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a language.

  ## Examples

      iex> delete_language(language)
      {:ok, %Language{}}

      iex> delete_language(language)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_language(Language.t()) :: {:ok, Language.t()} | {:error, Ecto.Changeset.t()}
  def delete_language(%Language{} = language) do
    language
    |> Language.delete_changeset()
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking language changes.

  ## Examples

      iex> change_language(language)
      %Ecto.Changeset{data: %Language{}}

  """
  @spec change_language(Language.t(), map()) :: Ecto.Changeset.t()
  def change_language(%Language{} = language, attrs \\ %{}) do
    Language.changeset(language, attrs)
  end

  @doc """
  Upserts a language based on the unique indexes in the table. If there is a match
  it returns the existing contact, else it creates a new one
  """
  @spec language_upsert(map()) :: {:ok, Language.t()}
  def language_upsert(attrs) do
    language =
      Repo.insert!(
        change_language(%Language{}, attrs),
        on_conflict: [set: [label: attrs.label]],
        conflict_target: [:label, :locale]
      )

    {:ok, language}
  end
end
