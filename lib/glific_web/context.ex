defmodule GlificWeb.Context do
  @moduledoc """
  Setting the absinthe context, so we can store the current user there
  """
  @behaviour Plug

  import Plug.Conn
  import Ecto.Query, only: [where: 2]

  alias Glific.{Repo, User}

  def init(opts), do: opts

  def call(conn, _) do
    context = build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

  @doc """
  Return the current user context based on the authorization header
  """
  def build_context(conn) do
    IO.inspect(conn)
    with {:ok, current_user} <- conn.get("current_user") do
      %{current_user: current_user}
    else
      _ -> %{}
    end
  end

end
