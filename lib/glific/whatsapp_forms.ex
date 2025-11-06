defmodule Glific.WhatsappForms do
  @moduledoc """
  WhatsApp Forms context module. This module provides functions for managing WhatsApp forms.
  """
  import Ecto.Query, warn: false
  alias Glific.Providers.Gupshup.WhatsappForms.ApiClient
  alias Glific.Repo
  alias Glific.WhatsappForms.WhatsappForm

  require Logger

  @doc """
    Publishes a WhatsApp form through the configured provider (e.g., Gupshup).
  """
  @spec publish_whatsapp_form(WhatsappForm.t()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def publish_whatsapp_form(%WhatsappForm{} = form) do
    case ApiClient.publish_wa_form(form.meta_flow_id, form.organization_id) do
      {:ok, _response} ->
        update_form_status(form, :published)

      {:error, reason} ->
        Logger.error("Failed to publish WhatsApp form #{form.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deactivates a WhatsApp form by its Meta Flow ID.
  """
  @spec deactivate_wa_form(WhatsappForm.t()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  def deactivate_wa_form(form) do
    update_form_status(form, :inactive)
  end

  @doc """
  Fetches a WhatsApp form from the database using its whatsapp form ID.
  """
  @spec get_whatsapp_form_by_id(String.t()) ::
          {:ok, WhatsappForm.t()} | {:error, any()}
  def get_whatsapp_form_by_id(form_id) do
    Repo.fetch_by(WhatsappForm, %{id: form_id})
  end

  @doc """
  Returns the list of whatsapp forms.
  """
  @spec list_whatsapp_forms(map()) :: [WhatsappForm.t()]
  def list_whatsapp_forms(args),
    do: Repo.list_filter(args, WhatsappForm, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of whatsapp forms
  """
  @spec count_whatsapp_forms(map()) :: integer
  def count_whatsapp_forms(args),
    do: Repo.count_filter(args, WhatsappForm, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from(q in query, where: q.status == ^status)

      {:name, name}, query ->
        from(q in query, where: q.name == ^name)

      {:meta_flow_id, meta_flow_id}, query ->
        from(q in query, where: q.meta_flow_id == ^meta_flow_id)
    end)
  end

  @spec update_form_status(WhatsappForm.t(), atom()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  defp update_form_status(%WhatsappForm{} = form, new_status) do
    form
    |> Ecto.Changeset.change(status: new_status)
    |> Repo.update()
  end
end
