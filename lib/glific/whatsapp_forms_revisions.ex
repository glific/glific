defmodule Glific.WhatsappFormsRevisions do
  @moduledoc """
   Context module for managing WhatsApp form revisions.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Repo,
    WhatsappForms,
    WhatsappForms.WhatsappFormRevision
  }

  @doc """
  Saves a new revision for a WhatsApp form
  """
  @spec save_revision(map(), map()) :: {:ok, WhatsappFormRevision.t()} | {:error, any()}
  def save_revision(attrs, user) do
    payload = %{
      whatsapp_form_id: attrs.whatsapp_form_id,
      definition: attrs.definition,
      user_id: user.id,
      organization_id: user.organization_id
    }

    with {:ok, revision} <- create_revision(payload),
         {:ok, _form} <-
           WhatsappForms.update_revision_id(attrs.whatsapp_form_id, revision.id) do
      {:ok, revision}
    else
      error -> error
    end
  end

  @doc """
  Creates a new revision
  """
  @spec create_revision(map()) :: {:ok, WhatsappFormRevision.t()} | {:error, Ecto.Changeset.t()}
  def create_revision(attrs) do
    %WhatsappFormRevision{}
    |> WhatsappFormRevision.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a specific revision by ID
  """
  @spec get_whatsapp_form_revision(non_neg_integer()) ::
          {:ok, WhatsappFormRevision.t()} | {:error, [String.t()]}
  def get_whatsapp_form_revision(revision_id) do
    Repo.fetch_by(WhatsappFormRevision, %{id: revision_id})
  end

  @doc """
  Lists the last N revisions for a WhatsApp form.
  The current revision (the one the form points to) is marked with is_current: true
  and placed at the top of the list.
  """
  @spec list_revisions(non_neg_integer(), non_neg_integer()) :: [map()]
  def list_revisions(whatsapp_form_id, limit) do
    current_revision_id =
      WhatsappForms.WhatsappForm
      |> where([f], f.id == ^whatsapp_form_id)
      |> select([f], f.revision_id)
      |> Repo.one()

    WhatsappFormRevision
    |> where([r], r.whatsapp_form_id == ^whatsapp_form_id)
    |> order_by([r], desc: r.revision_number)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn revision ->
      Map.put(revision, :is_current, revision.id == current_revision_id)
    end)
    |> Enum.sort_by(& &1.is_current, :desc)
  end

  @doc """
  Reverts a WhatsApp form to a specific revision
  """
  @spec revert_to_revision(String.t(), non_neg_integer()) ::
          {:ok, WhatsappFormRevision.t()} | {:error, any()}
  def revert_to_revision(whatsapp_form_id, revision_id) do
    whatsapp_form_id = String.to_integer(whatsapp_form_id)

    with {:ok, revision} <- get_whatsapp_form_revision(revision_id),
         true <- revision.whatsapp_form_id == whatsapp_form_id,
         {:ok, _form} <- WhatsappForms.update_revision_id(whatsapp_form_id, revision.id) do
      {:ok, revision}
    else
      false -> {:error, "Revision does not belong to this form"}
      error -> error
    end
  end

  @doc """
  Provides a default WhatsApp form definition
  """
  @spec default_definition() :: map()
  def default_definition do
    %{
      "screens" => [
        %{
          "data" => %{},
          "id" => "screen_bcvvpc",
          "layout" => %{
            "children" => [
              %{
                "children" => [
                  %{"text" => "Text", "type" => "TextHeading"},
                  %{
                    "label" => "Continue",
                    "on-click-action" => %{"name" => "complete", "payload" => %{}},
                    "type" => "Footer"
                  }
                ],
                "name" => "flow_path",
                "type" => "Form"
              }
            ],
            "type" => "SingleColumnLayout"
          },
          "terminal" => true,
          "title" => "Screen 1"
        }
      ],
      "version" => "7.3"
    }
  end
end
