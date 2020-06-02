defmodule Glific.Repo do
  @moduledoc """
  We add a few functions to make our life easier with a few helper functions that ecto does
  not provide.
  """

  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Glific version of get, which returns a tuple with an :ok | :error as the first element
  """
  @spec fetch(Ecto.Queryable.t(), term(), Keyword.t()) :: {atom(), Ecto.Schema.t() | String.t()}
  def fetch(queryable, id, opts \\ []) do
    case get(queryable, id, opts) do
      nil -> {:error, ["#{queryable} #{id}", "Resource not found"]}
      resource -> {:ok, resource}
    end
  end

  @doc """
  Glific version of get_by, which returns a tuple with an :ok | :error as the first element
  """
  @spec fetch_by(Ecto.Queryable.t(), Keyword.t() | map(), Keyword.t()) :: {atom(), Ecto.Schema.t() | String.t()}
  def fetch_by(queryable, clauses, opts \\ []) do
    case get_by(queryable, clauses, opts) do
      nil -> {:error, "Resource not found"}
      resource -> {:ok, resource}
    end
  end

end
