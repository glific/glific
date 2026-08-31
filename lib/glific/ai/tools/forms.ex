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
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "form_responses",
        description: """
        Lists what contacts submitted through a form, newest first. Use this to
        check whether submissions are arriving at all, and what they contain.
        """,
        parameters: [
          form_id: [type: :pos_integer, doc: "Only responses to this form, from list_forms"],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
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

    {:ok, forms}
  end

  def run("form_responses", args) do
    responses =
      WhatsappFormResponse
      |> maybe_for_form(args[:form_id])
      |> order_by([r], desc: r.submitted_at)
      |> limit(^min(args[:limit], 100))
      |> select([r], %{
        whatsapp_form_id: r.whatsapp_form_id,
        contact_id: r.contact_id,
        raw_response: r.raw_response,
        submitted_at: r.submitted_at
      })
      |> Repo.all()

    {:ok, responses}
  end

  @spec maybe_for_form(Ecto.Queryable.t(), non_neg_integer() | nil) :: Ecto.Queryable.t()
  defp maybe_for_form(query, nil), do: query
  defp maybe_for_form(query, id), do: where(query, [r], r.whatsapp_form_id == ^id)
end
