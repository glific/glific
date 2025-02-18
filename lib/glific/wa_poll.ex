defmodule Glific.WaPoll do
  @moduledoc """
  The whatsapp poll Context, which encapsulates and manages whatsapp poll
  """
  alias Glific.{Repo, WAGroup.WaPoll}
  import Ecto.Query, warn: false

  @doc """
  Creates an wa_poll

  ## Examples

      iex> create_wa_poll(%{field: value})
      {:ok, %WaPoll{}}

      iex> create_wa_poll(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_wa_poll(map()) :: {:ok, WaPoll.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_poll(attrs) do
    with :ok <- validate_options(attrs) do
      %WaPoll{}
      |> WaPoll.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec validate_options(map()) :: :ok | {:error, String.t()}
  defp validate_options(attrs) do
    options = attrs[:poll_content]["options"]

    validate_option_count(options)
    |> validate_option_uniqueness()
  end

  @spec validate_option_count(list()) :: {:ok, list()} | {:error, String.t()}
  defp validate_option_count(options) do
    if length(options) > 12 do
      {:error, "The number of options should be up to 12 only, but got #{length(options)}."}
    else
      {:ok, options}
    end
  end

  @spec validate_option_uniqueness({:ok, list()} | {:error, String.t()}) ::
          :ok | {:error, String.t()}
  defp validate_option_uniqueness({:error, _} = error), do: error

  defp validate_option_uniqueness({:ok, options}) do
    unique_names = Enum.uniq_by(options, & &1["name"])

    if length(options) != length(unique_names) do
      {:error, "Duplicate options detected"}
    else
      :ok
    end
  end

  @doc """
  Fetches a single wa_poll

  Returns `Resource not found` if the wa_poll does not exist.

  ## Examples

      iex> fetch_wa_poll(123)
        {:ok, %WaPol{}}

      iex> fetch_wa_poll(456)
        {:error, ["Elixir.Glific.WaGroup.WaPoll", "Resource not found"]}

  """
  @spec fetch_wa_poll(integer) :: {:ok, WaPoll.t()} | {:error, any}
  def fetch_wa_poll(id),
    do: Repo.fetch_by(WaPoll, %{id: id})

  @doc """
  Returns the list of wa poll

  ## Examples

      iex> list_wa_polls()
      [%WaPoll{}, ...]

  """
  @spec list_wa_polls(map()) :: [WaPoll.t()]
  def list_wa_polls(args),
    do: Repo.list_filter(args, WaPoll, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of wa polls, using the same filter as list_wa_polls
  """
  @spec count_wa_polls(map()) :: integer
  def count_wa_polls(args),
    do: Repo.count_filter(args, WaPoll, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:label, label}, query ->
        from(q in query, where: ilike(field(q, :label), ^"%#{label}%"))

      {:allow_multiple_answer, allow_multiple_answer}, query ->
        from(q in query, where: q.allow_multiple_answer == ^allow_multiple_answer)

      _, query ->
        query
    end)
  end

  @doc """
  Deletes an whatsapp poll
  ## Examples

      iex> delete_wa_poll(waPoll)
      {:ok, %waPoll{}}

      iex> delete_wa_poll(waPoll)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_wa_poll(WaPoll.t()) ::
          {:ok, WaPoll.t()} | {:error, Ecto.Changeset.t()}
  def delete_wa_poll(%WaPoll{} = waPoll) do
    waPoll
    |> WaPoll.changeset(%{})
    |> Repo.delete()
  end

  @doc """
  Make a copy of a wa_poll
  """
  @spec copy_wa_poll(WaPoll.t(), map()) ::
          {:ok, WaPoll.t()} | {:error, String.t()}
  def copy_wa_poll(wa_poll, attrs) do
    attrs =
      %{
        poll_content: wa_poll.poll_content,
        allow_multiple_answer: wa_poll.allow_multiple_answer
      }
      |> Map.merge(attrs)

    %WaPoll{}
    |> WaPoll.changeset(attrs)
    |> Repo.insert()
  end
end
