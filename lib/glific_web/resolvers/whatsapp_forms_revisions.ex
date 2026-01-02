defmodule GlificWeb.Resolvers.WhatsappFormsRevisions do
  @moduledoc """
  Resolvers for managing WhatsApp form revisions
  """

  alias Glific.WhatsappFormsRevisions

  @doc """
  Saves a new revision for a WhatsApp form
  """
  @spec save_revision(any(), map(), map()) :: {:ok, any()} | {:error, any()}
  def save_revision(_, %{input: input}, %{context: %{current_user: user}}) do
    case WhatsappFormsRevisions.save_revision(input, user) do
      {:ok, revision} -> {:ok, %{whatsapp_form_revision: revision}}
      error -> error
    end
  end

  @doc """
  Gets a specific revision by ID
  """
  @spec whatsapp_form_revision(any(), map(), any()) :: {:ok, any()} | {:error, any()}
  def whatsapp_form_revision(_, %{id: id}, _) do
    case WhatsappFormsRevisions.get_whatsapp_form_revision(id) do
      {:ok, revision} -> {:ok, %{whatsapp_form_revision: revision}}
      error -> error
    end
  end

  @doc """
  Lists the last N revisions for a WhatsApp form
  """
  @spec list_revisions(any(), map(), any()) :: {:ok, list()} | {:error, any()}
  def list_revisions(_, %{whatsapp_form_id: whatsapp_form_id} = args, _) do
    limit = Map.get(args, :limit, 10)
    revisions = WhatsappFormsRevisions.list_revisions(whatsapp_form_id, limit)
    {:ok, revisions}
  end

  @doc """
  Reverts a WhatsApp form to a specific revision
  """
  @spec revert_to_revision(any(), map(), any()) :: {:ok, any()} | {:error, any()}
  def revert_to_revision(_, %{whatsapp_form_id: whatsapp_form_id, revision_id: revision_id}, _) do
    case WhatsappFormsRevisions.revert_to_revision(whatsapp_form_id, revision_id) do
      {:ok, revision} -> {:ok, %{whatsapp_form_revision: revision}}
      error -> error
    end
  end
end
