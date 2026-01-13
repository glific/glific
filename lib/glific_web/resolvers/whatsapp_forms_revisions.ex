defmodule GlificWeb.Resolvers.WhatsappFormsRevisions do
  @moduledoc """
  Resolvers for managing WhatsApp form revisions
  """

  alias Glific.WhatsappFormsRevisions

  @doc """
  Saves a new revision for a WhatsApp form
  """
  @spec save_revision(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def save_revision(_, %{input: input}, %{context: %{current_user: user}}) do
    with {:ok, revision} <- WhatsappFormsRevisions.save_revision(input, user) do
      {:ok, %{whatsapp_form_revision: revision}}
    end
  end

  @doc """
  Gets a specific revision by ID
  """
  @spec whatsapp_form_revision(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def whatsapp_form_revision(_, %{id: id}, _) do
    with {:ok, revision} <- WhatsappFormsRevisions.get_whatsapp_form_revision(id) do
      {:ok, %{whatsapp_form_revision: revision}}
    end
  end

  @doc """
  Lists the last N revisions for a WhatsApp form
  """
  @spec list_revisions(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, list()} | {:error, any()}
  def list_revisions(_, %{whatsapp_form_id: whatsapp_form_id} = args, _) do
    limit = Map.get(args, :limit, 10)
    revisions = WhatsappFormsRevisions.list_revisions(whatsapp_form_id, limit)
    {:ok, revisions}
  end

  @doc """
  Reverts a WhatsApp form to a specific revision
  """
  @spec revert_to_revision(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def revert_to_revision(_, %{whatsapp_form_id: whatsapp_form_id, revision_id: revision_id}, _) do
    with {:ok, revision} <-
           WhatsappFormsRevisions.revert_to_revision(whatsapp_form_id, revision_id) do
      {:ok, %{whatsapp_form_revision: revision}}
    end
  end
end
