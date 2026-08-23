defmodule Glific.AI.Tools.DescribeTable do
  @moduledoc """
  Returns the allow-listed field names for one `Glific.ChatbotDiagnose` table.

  Kept separate from `Glific.AI.Tools.QueryOrgData` so that tool's description does not have to
  enumerate every table's fields inline — enumerating all ~55 tables' fields in one description
  would cost enormous prompt tokens on every turn and give the model nothing useful to act on
  until it already knows which table it wants. The intended sequence is: describe a table, then
  query it with the field names `describe_table` returned.
  """

  use Glific.AI.Tool

  alias Glific.AI.Tool.Context
  alias Glific.ChatbotDiagnose

  @tables ChatbotDiagnose.tables()

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "describe_table"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description,
    do:
      "Returns the field names available on one organisation data table. Call this before " <>
        "query_org_data for any table you have not already described in this conversation."

  @doc false
  @spec parameters() :: keyword()
  @impl true
  def parameters do
    [table: [type: {:in, @tables}, required: true, doc: "The table to describe."]]
  end

  @doc false
  @spec run(map(), Context.t()) :: {:ok, term()} | {:error, String.t()}
  @impl true
  def run(%{"table" => table}, %Context{}) when is_binary(table) do
    case ChatbotDiagnose.allowed_fields(table) do
      [] -> {:error, "Unknown table: #{table}"}
      fields -> {:ok, %{table: table, fields: Enum.map(fields, &Atom.to_string/1)}}
    end
  end

  def run(_args, %Context{}), do: {:error, "table is required"}
end
