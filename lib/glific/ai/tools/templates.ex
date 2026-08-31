defmodule Glific.AI.Tools.Templates do
  @moduledoc """
  Reads about message templates, including the approval status of WhatsApp HSM
  templates — which is what to check first when a template will not send.
  """

  alias Glific.{Templates, Templates.InteractiveTemplates}

  @behaviour Glific.AI.Tool

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "list_templates",
        description: """
        Lists this organisation's message templates with their labels, shortcodes
        and bodies. For WhatsApp HSM templates it also gives the approval status,
        which is what to check when a template is not sending.
        """,
        parameters: [
          label: [type: :string, doc: "Only return templates whose label contains this text"],
          is_hsm: [
            type: :boolean,
            doc: "Return only HSM templates (true) or only session templates (false)"
          ],
          status: [
            type: :string,
            doc: ~s(Only templates with this approval status, e.g. "APPROVED")
          ],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_interactive_templates",
        description: """
        Lists this organisation's interactive templates — the list and button
        messages flows send. Use this to check what options a contact was
        actually offered.
        """,
        parameters: [
          label: [type: :string, doc: "Only templates whose label contains this text"],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
  def run("list_templates", args) do
    filter =
      %{}
      |> maybe_put(:label, args[:label])
      |> maybe_put(:is_hsm, args[:is_hsm])
      |> maybe_put(:status, args[:status])

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
          is_active: &1.is_active,
          language_id: &1.language_id
        }
      )

    {:ok, templates}
  end

  def run("list_interactive_templates", args) do
    filter = if args[:label], do: %{label: args[:label]}, else: %{}

    templates =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> InteractiveTemplates.list_interactives()
      |> Enum.map(
        &%{
          id: &1.id,
          label: &1.label,
          type: &1.type,
          interactive_content: &1.interactive_content,
          send_with_title: &1.send_with_title,
          language_id: &1.language_id
        }
      )

    {:ok, templates}
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(filter, _key, nil), do: filter
  defp maybe_put(filter, key, value), do: Map.put(filter, key, value)
end
