defmodule GlificWeb.ContextPlug do
  @moduledoc """
  Setting the absinthe context, so we can store the current user there
  """
  @behaviour Plug

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _) do
    context = build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

  @doc """
  Return the current user context based on the authorization header
  """
  @spec build_context(Plug.Conn.t()) :: map()
  def build_context(conn) do
    current_user = conn.assigns[:current_user]

    if current_user != nil do
      # Track user for ExAudit
      ExAudit.track(user_id: current_user.id, organization_id: current_user.organization_id)

      # Add the current_user to the Process memory
      Glific.Repo.put_current_user(current_user)
      Glific.RepoReplica.put_current_user(current_user)

      if current_user.language,
        do: Gettext.put_locale(current_user.language.locale)

      %{current_user: current_user}
    else
      %{}
    end
  end
end
