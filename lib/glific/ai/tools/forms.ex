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

  @impl Glific.AI.Tool
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

  @impl Glific.AI.Tool
  def run("list_forms", args) do
    # No `order`: this context orders by a `label` column the table lacks.
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
    |> limit(100)
    |> select(
      [r],
      {r.whatsapp_form_id,
       %{contact_id: r.contact_id, raw_response: r.raw_response, submitted_at: r.submitted_at}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
