use Wormwood.GQLCase

defmodule Glific.TestHelpers do
  @moduledoc """
  A module for defining Helper funcations in test cases
  """
  def auth_query_gql_by(query, options) do
    [user | _] =  Glific.Users.list_users()
    options = Keyword.put_new(options, :context, %{:current_user => user})
    query_gql_by(query, options)
  end
end
