defmodule GlificWeb.Schema.GenericTypes do
  @moduledoc """
  GraphQL Representation of common data representations used across different
  Glific's DataType
  """

  use Absinthe.Schema.Notation

  @desc "An error encountered trying to persist input"
  object :input_error do
    field :key, non_null(:string)
    field :message, non_null(:string)
  end

  @desc "Lets collapse sort order, limit and offset into its own little groups"
  input_object :opts do
    field(:order, type: :sort_order, default_value: :asc)
    field(:limit, :integer)
    field(:offset, :integer, default_value: 0)
  end

  @desc """
  A generic status results for calls that dont return a value.
  Typically this is for delete operations
  """
  object :generic_result do
    field :status, non_null(:api_status_enum)
    field :errors, list_of(:input_error)
  end

  scalar :gid do
    description("""
    The `gid` scalar appears in JSON as a String. The string appears to
    the glific backend as an integer
    """)

    parse(&parse_maybe_integer/1)
    serialize(&Integer.to_string/1)
  end

  @doc """
  A forgivable parser which allows integers or strings to represent integers
  """
  @spec parse_maybe_integer(Absinthe.Blueprint.Input.String.t()) :: {:ok, integer} | :error
  def parse_maybe_integer(%Absinthe.Blueprint.Input.String{value: value}) when is_binary(value) do
    Glific.parse_maybe_integer(value)
  end

  def parse_maybe_integer(_), do: :error

  scalar :json, name: "Json" do
    description("""
    A generic json type so return the results as json object
    """)

    serialize(&Poison.encode!/1)
    parse(&decode_json/1)
  end

  @spec decode_json(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  defp decode_json(%Absinthe.Blueprint.Input.String{value: value}) do
    case Jason.decode(value) do
      {:ok, result} -> {:ok, result}
      _ -> :error
    end
  end

  defp decode_json(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp decode_json(_) do
    :error
  end

  # Enable Ecto UUID scalar for grapql

  scalar :uuid4, name: "UUID4" do
    description("""
    The `UUID4` scalar type represents UUID4 compliant string data, represented as UTF-8
    character sequences. The UUID4 type is most often used to represent unique
    human-readable ID strings.
    """)

    serialize(&encode_uuid4/1)
    parse(&decode_uuid4/1)
  end

  @spec decode_uuid4(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode_uuid4(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp decode_uuid4(%Absinthe.Blueprint.Input.String{value: value}) do
    Ecto.UUID.cast(value)
  end

  defp decode_uuid4(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp decode_uuid4(_) do
    :error
  end

  defp encode_uuid4(value), do: value


  # We will move this logic somewhere else in the future because it's not generic
  scalar :role_lable, name: "RoleLable" do
    description("""
    Convert a string/atom to lable (camel case)
    """)

    serialize(&encode_label/1)
    parse(&parse_label/1)
  end


  @spec parse_label(Absinthe.Blueprint.Input.String.t) :: {:ok, String.t} | :error
  @spec parse_label(Absinthe.Blueprint.Input.Null.t) :: {:ok, nil}
  defp parse_label(%Absinthe.Blueprint.Input.String{value: label}) do
    cond do
      is_binary(label) ->
          label = label
          |> String.downcase()
          |> String.to_existing_atom()
          {:ok, label}

      true ->  {:ok, label}
    end
  end

  defp parse_label(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end
  defp parse_label(_) do
    :error
  end


  defp encode_label(label) when is_atom(label) do
    label
    |> Atom.to_string()
    |> String.capitalize()
  end

  defp encode_label(label) when is_binary(label) do
    label
    |> String.capitalize()
  end

  defp encode_label(label), do: label

end
