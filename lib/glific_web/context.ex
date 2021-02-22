defmodule GlificWeb.Context do
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
    Absinthe.Plug.put_options(conn, nonce: :erlang.unique_integer())
  end

  @doc """
  Return the current user context based on the authorization header
  """
  @spec build_context(Plug.Conn.t()) :: map()
  def build_context(conn) do
    current_user = conn.assigns[:current_user]

    # Add the current_user to the Process memory
    Glific.Repo.put_current_user(current_user)

    context = %{nonce: :erlang.unique_integer()}
    if current_user != nil do
      Map.put(context, :current_user, current_user)
    else
      context
    end
  end
end
