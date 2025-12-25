defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
    Resolvers for managing WhatsApp forms, including creation, updates, publishing, deactivation, and querying.
  """

  alias Glific.{
    WhatsappForms,
    WhatsappForms.WhatsappForm
  }

  @doc """
  Retrieves a WhatsApp form by ID
  """
  @spec whatsapp_form(any(), %{id: non_neg_integer()}, Absinthe.Resolution.t()) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}} | {:error, any()}
  def whatsapp_form(_, %{id: id}, _) do
    with {:ok, whatsapp_form} <-
           WhatsappForms.get_whatsapp_form_by_id(id) do
      {:ok, %{whatsapp_form: whatsapp_form}}
    end
  end

  @doc """
  Lists all available WhatsApp form categories
  """
  @spec list_whatsapp_form_categories(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, list(String.t())}
  def list_whatsapp_form_categories(_parent, _args, _resolution) do
    WhatsappForms.list_whatsapp_form_categories()
  end

  @doc """
  Creates a WhatsApp form
  """
  @spec create_whatsapp_form(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_whatsapp_form(_, %{input: params}, %{context: %{current_user: user}}) do
    WhatsappForms.create_whatsapp_form(params, user)
  end

  @doc """
  Updates a WhatsApp form
  """
  @spec update_whatsapp_form(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_whatsapp_form(_, %{id: id, input: params}, _) do
    with {:ok, form} <-
           WhatsappForms.get_whatsapp_form_by_id(id) do
      WhatsappForms.update_whatsapp_form(form, params)
    end
  end

  @doc """
    Publishes a WhatsApp form using its Meta Flow ID.
  """
  @spec publish_whatsapp_form(
          any(),
          %{id: non_neg_integer()},
          %{context: map()}
        ) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}}
          | {:error, String.t()}
  def publish_whatsapp_form(_parent, %{id: id}, _) do
    WhatsappForms.publish_whatsapp_form(id)
  end

  @doc """
  Get the count of whatsapp forms filtered by args
  """
  @spec count_whatsapp_forms(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_whatsapp_forms(_, args, _) do
    {:ok, WhatsappForms.count_whatsapp_forms(args)}
  end

  @doc """
  Get a specific whatsapp form by id
  """
  @spec get_whatsapp_form_by_id(any(), %{id: non_neg_integer()}, any()) ::
          {:ok, WhatsappForm.t()} | {:error, any()}
  def get_whatsapp_form_by_id(_, %{id: id}, _) do
    WhatsappForms.get_whatsapp_form_by_id(id)
  end

  @doc """
  Get the list of whatsapp forms filtered by args
  """
  @spec list_whatsapp_forms(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def list_whatsapp_forms(_, args, _) do
    {:ok, WhatsappForms.list_whatsapp_forms(args)}
  end

  @doc """
  Deactivates an existing WhatsApp form.
  """
  @spec deactivate_whatsapp_form(
          Absinthe.Resolution.t(),
          %{id: non_neg_integer()},
          %{context: map()}
        ) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}}
          | {:error, any()}
  def deactivate_whatsapp_form(_parent, %{id: id}, _) do
    WhatsappForms.deactivate_whatsapp_form(id)
  end

  @doc """
  activate WhatsApp form.
  """
  @spec activate_whatsapp_form(
          Absinthe.Resolution.t(),
          %{id: non_neg_integer()},
          %{context: map()}
        ) ::
          {:ok, %{whatsapp_form: WhatsappForm.t()}}
          | {:error, any()}
  def activate_whatsapp_form(_parent, %{id: id}, _) do
    WhatsappForms.activate_whatsapp_form(id)
  end

  @doc """
    Deletes a WhatsApp form belonging to a specific organization by its ID.
  """
  @spec delete_whatsapp_form(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_whatsapp_form(_, %{id: id}, _) do
    WhatsappForms.delete_whatsapp_form(id)
  end
end
