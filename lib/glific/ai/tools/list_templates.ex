defmodule Glific.AI.Tools.ListTemplates do
  @moduledoc """
  Lists the organisation's message templates, including the approval status of
  WhatsApp HSM templates.
  """

  @behaviour Glific.AI.Tool

  alias Glific.Templates

  @impl Glific.AI.Tool
  def name, do: "list_templates"

  @impl Glific.AI.Tool
  def description do
    """
    Lists this organisation's message templates with their labels, shortcodes and
    bodies. For WhatsApp HSM templates it also gives the approval status, which
    is what to check when a template is not sending.
    """
  end

  @impl Glific.AI.Tool
  def parameters do
    [
      label: [type: :string, doc: "Only return templates whose label contains this text"],
      is_hsm: [type: :boolean, doc: "Return only HSM templates (true) or only session templates"],
      limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
    ]
  end

  @impl Glific.AI.Tool
  def run(args) do
    filter =
      %{}
      |> maybe_put(:label, args[:label])
      |> maybe_put(:is_hsm, args[:is_hsm])

    templates =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> Templates.list_session_templates()
      |> Enum.map(
        &%{
          id: &1.id,
          label: &1.label,
          shortcode: &1.shortcode,
          body: &1.body,
          is_hsm: &1.is_hsm,
          status: &1.status,
          category: &1.category,
          is_active: &1.is_active
        }
      )

    {:ok, templates}
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(filter, _key, nil), do: filter
  defp maybe_put(filter, key, value), do: Map.put(filter, key, value)
end
