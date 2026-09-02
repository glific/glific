defmodule Glific.AI.Tools.Forms do
  @moduledoc """
  Reads about forms — the structured, in-chat questionnaires approved by Meta —
  and what contacts submitted through them.

  A form that will not open for a contact is almost always one whose status is
  not published, which is the first thing to check here.
  """

  import Ecto.Query

  alias Glific.{Repo, WhatsappForms, WhatsappForms.WhatsappFormResponse}

  @behaviour Glific.AI.Tool

  @per_form 25

  @doc "The form lookups this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "list_forms",
        description: """
        Lists this organisation's forms with their approval status from Meta.
        Check the status first when a form will not open for contacts.

        Add `include: ["responses"]` to see what contacts submitted, and whether
        submissions are arriving at all.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"],
          include: [
            type: {:list, {:in, ["responses"]}},
            default: [],
            doc: ~s(Add "responses" to see what contacts submitted)
          ]
        ]
      }
    ]
  end

  @doc "Reads the forms and their approval status, and optionally what contacts submitted."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("list_forms", args) do
    forms =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0}}
      |> WhatsappForms.list_whatsapp_forms()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          description: &1.description,
          status: &1.status,
          meta_flow_id: &1.meta_flow_id,
          categories: &1.categories
        }
      )

    {:ok, with_responses(forms, args[:include])}
  end

  @spec with_responses([map()], [String.t()]) :: [map()]
  defp with_responses(forms, include) do
    if "responses" in include do
      submissions = responses(Enum.map(forms, & &1.id))
      Enum.map(forms, &Map.put(&1, :responses, Map.get(submissions, &1.id, [])))
    else
      forms
    end
  end

  @spec responses([non_neg_integer()]) :: map()
  defp responses(form_ids) do
    WhatsappFormResponse
    |> where([r], r.whatsapp_form_id in ^form_ids)
    |> order_by([r], desc: r.submitted_at)
    |> select(
      [r],
      {r.whatsapp_form_id,
       %{contact_id: r.contact_id, raw_response: r.raw_response, submitted_at: r.submitted_at}}
    )
    |> per_parent(@per_form)
  end

  @spec per_parent(Ecto.Queryable.t(), pos_integer()) :: map()
  defp per_parent(query, take) do
    query
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {parent, rows} ->
      {parent,
       if(length(rows) > take,
         do: %{truncated: true, showing: Enum.take(rows, take), of: length(rows)},
         else: rows
       )}
    end)
  end
end
