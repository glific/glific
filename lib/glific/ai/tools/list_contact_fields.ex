defmodule Glific.AI.Tools.ListContactFields do
  @moduledoc """
  Lists the contact fields this organisation has defined.

  Flows read and write these by shortcode, so the real list is what stops an
  answer inventing a field that does not exist.
  """

  @behaviour Glific.AI.Tool

  alias Glific.Flows.ContactField

  @impl Glific.AI.Tool
  def name, do: "list_contact_fields"

  @impl Glific.AI.Tool
  def description do
    """
    Lists the contact fields defined in this organisation, with their shortcodes
    and value types. Use this before referring to a contact field by name, rather
    than assuming one exists.
    """
  end

  @impl Glific.AI.Tool
  def parameters do
    [limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]]
  end

  @impl Glific.AI.Tool
  def run(args) do
    fields =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> ContactField.list_contacts_fields()
      |> Enum.map(
        &%{name: &1.name, shortcode: &1.shortcode, value_type: &1.value_type, scope: &1.scope}
      )

    {:ok, fields}
  end
end
