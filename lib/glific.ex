defmodule Glific do
  import Ecto.Changeset

  @moduledoc """
  Glific keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.

  For now we'll keep some commonly used functions here, until we need
  a new file
  """

  @doc """
  Wrapper to return :ok/:error when parsing strings to potential integers
  """
  @spec parse_maybe_integer(String.t() | integer) :: {:ok, integer} | :error
  def parse_maybe_integer(value) when is_integer(value),
    do: {:ok, value}

  def parse_maybe_integer(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      {_num, _rest} -> :error
      :error -> :error
    end
  end

  @doc """
  Validates inputed shortcode, if shortcode is invalid it returns message that the shortcode is invalid
  along with the valid shortcode.
  """
  @spec(
    validate_shortcode(Ecto.Changeset.t()) :: Ecto.Changeset.t() | Ecto.Changeset.t(),
    atom(),
    String.t()
  )
  def validate_shortcode(%Ecto.Changeset{} = changeset) do
    shortcode = Map.get(changeset.changes, :shortcode)
    valid_shortcode = string_clean(shortcode)

    if valid_shortcode == shortcode,
      do: changeset,
      else:
        add_error(
          changeset,
          :shortcode,
          "Invalid shortcode, valid shortcode will be  #{valid_shortcode}"
        )
  end

  @doc """
  Lets get rid of all non valid characters. We are assuming any language and hence using unicode syntax
  and not restricting ourselves to alphanumeric
  """
  @spec string_clean(String.t() | nil) :: String.t() | nil
  def string_clean(str) when is_nil(str) or str == "", do: str

  def string_clean(str),
    do:
      str
      |> String.replace(~r/[\p{P}\p{S}\p{Z}\p{C}]+/u, "")
      |> String.downcase()
      |> String.trim()
end
