defmodule Glific.WaPoll do
  @moduledoc """
  The whatsapp poll Context, which encapsulates and manages whatsapp poll
  """
  alias Glific.{WaGroup.WaPoll, Repo}

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
    %WaPoll{}
    |> WaPoll.changeset(attrs)
    |> Repo.insert()
  end
end
