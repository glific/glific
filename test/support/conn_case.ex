defmodule GlificWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GlificWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  alias Glific.{
    Fixtures,
    Partners,
    Repo
  }

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import GlificWeb.ConnCase

      alias GlificWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint GlificWeb.Endpoint

      use GlificWeb, :verified_routes

      defmacro auth_query_gql_by(query, user, options \\ []) do
        quote do
          options_user =
            Keyword.put_new(unquote(options), :context, %{current_user: unquote(user)})

          query_gql_by(unquote(query), options_user)
        end
      end
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    organization_id = 1
    organization_id |> Partners.get_organization!() |> Partners.fill_cache()

    manager = Fixtures.user_fixture(%{roles: ["manager"]})

    Glific.Repo.put_organization_id(1)
    Glific.RepoReplica.put_organization_id(1)
    Glific.Repo.put_current_user(manager)
    Glific.RepoReplica.put_current_user(manager)
    Fixtures.set_bsp_partner_tokens(organization_id)

    Code.compiler_options(ignore_module_conflict: true)

    {
      :ok,
      conn: Phoenix.ConnTest.build_conn() |> Plug.Conn.assign(:organization_id, organization_id),
      organization_id: organization_id,
      user: Fixtures.user_fixture(),
      manager: manager,
      staff: Fixtures.user_fixture(%{roles: ["staff"]}),
      glific_admin: Fixtures.user_fixture(%{roles: ["glific_admin"]}),
      global_schema: Application.fetch_env!(:glific, :global_schema)
    }
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  @spec register_and_log_in_user(Plug.Conn.t()) :: any()
  def register_and_log_in_user(%{conn: conn}) do
    user = Glific.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  @spec log_in_user(Plug.Conn.t(), any()) :: any()
  def log_in_user(conn, user) do
    token = Glific.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
