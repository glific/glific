defmodule GlificWeb.Schema.Middleware.PutSubscriberOrganization do
  @moduledoc """
  Sets the subscriber's organization id on the process resolving a subscription document.

  A publish on another node is relayed and resolved on the subscriber's node in a fresh process,
  so field resolvers that query `Repo` directly have no organization id to scope by.
  """

  @behaviour Absinthe.Middleware

  alias Glific.Repo

  @doc false
  @spec call(Absinthe.Resolution.t(), term()) :: Absinthe.Resolution.t()
  def call(%{context: %{current_user: %{organization_id: organization_id}}} = resolution, _) do
    # Only the organization id: on the publishing node this runs in the publisher's process,
    # where swapping in the subscriber as current user would change its permission filtering.
    Repo.put_organization_id(organization_id)
    resolution
  end

  def call(resolution, _), do: resolution
end
