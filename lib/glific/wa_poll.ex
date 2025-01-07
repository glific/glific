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
  @spec create_wa_poll(map()) ::
          {:ok, WaPoll.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_poll(attrs) do
    with :ok <-
           validate_options(attrs) do
      %WaPoll{}
      |> WaPoll.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec validate_options(map()) :: :ok | {:error, String.t()}
  defp validate_options(attrs) do
    options = attrs[:poll_content]["options"]
    options_count = length(options)

    # Check if there are more than 12 options
    if options_count > 12 do
      {:error, "The number of options should be up to 12 only, but got #{options_count}."}
    else
      # Check for duplicate option names
      option_names = Enum.map(options, fn option -> option["name"] end)
      duplicates = option_names -- Enum.uniq(option_names)

      if duplicates != [] do
        {:error, "Duplicate options detected: #{Enum.join(duplicates, ", ")}."}
      else
        :ok
      end
    end
  end
end
