defmodule GlificWeb.Resolvers.Billings do
  @moduledoc """
  Billing Resolver which sits between the GraphQL schema and Glific Billing Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Messages, Repo, Partners.Billing}

  @doc """
  Get a specific billing by id
  """
  @spec billing(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def billing(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, billing} <- Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{billing: billing}}
  end

  @doc """
  Get the list of billings filtered by args
  """
  @spec billings(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Billing]}
  def billings(_, args, _) do
    {:ok, Billing.list_billings(args)}
  end

  @doc """
  Get the count of billings filtered by args
  """
  @spec count_billings(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_billings(_, args, _) do
    {:ok, Billing.count_billings(args)}
  end

  @doc false
  @spec create_billing(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_billing(_, %{input: params}, _) do
    with {:ok, billing} <- Billing.create_billing(params) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec update_billing(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_billing(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, billing} <- Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}),
         {:ok, billing} <- Billing.update_billing(Billing, params) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec delete_billing(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_billing(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, billing} <- Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}),
         {:ok, billing} <- Billing.delete_billing(Billing) do
      {:ok, billing}
    end
  end

  @doc false
  @spec create_message_billing(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_message_billing(_, %{input: params}, _) do
    with {:ok, message_billing} <- Billing.create_message_billing(params) do
      {:ok, %{message_billing: message_billing}}
    end
  end

  @doc false
  @spec update_message_billings(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_message_billings(_, %{input: params}, _) do
    # we should add sanity check whether message and billing belongs to the organization of the current user
    message_billings = Billing.MessageBilling.update_message_billings(params)
    {:ok, message_billings}
  end

  @doc false
  @spec create_contact_billing(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_billing(_, %{input: params}, _) do
    with {:ok, contact_billing} <- Billing.create_contact_billing(params) do
      {:ok, %{contact_billing: contact_billing}}
    end
  end

  @doc """
  Creates and/or deletes a list of contact billings, each billing attached to the same contact
  """
  @spec update_contact_billings(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact_billings(_, %{input: params}, _) do
    # we should add sanity check whether contact and billing belongs to the organization of the current user
    contact_billings = Billing.ContactBilling.update_contact_billings(params)
    {:ok, contact_billings}
  end

  @doc false
  @spec mark_contact_messages_as_read(Absinthe.Resolution.t(), %{contact_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def mark_contact_messages_as_read(_, %{contact_id: contact_id}, %{
        context: %{current_user: user}
      }) do
    Messages.mark_contact_messages_as_read(contact_id, user.organization_id)
    {:ok, contact_id}
  end

  @doc """
  Create entry for billing mapped to template
  """
  @spec create_template_billing(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_template_billing(_, %{input: params}, _) do
    with {:ok, template_billing} <- Billing.create_template_billing(params) do
      {:ok, %{template_billing: template_billing}}
    end
  end

  @doc """
  Creates and/or deletes a list of template billings, each billing attached to the same template
  """
  @spec update_template_billings(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_template_billings(_, %{input: params}, _) do
    # we should add sanity check whether template and billing belongs to the organization of the current user
    template_billings = Billing.TemplateBilling.update_template_billings(params)
    {:ok, template_billings}
  end
end
