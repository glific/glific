defmodule Glific.WaPoll do
  @moduledoc """
  The whatsapp poll Context, which encapsulates and manages whatsapp poll
  """
  alias Glific.{Repo, WaGroup.WaPoll}

  @doc """
  Creates an interactive template

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
end
