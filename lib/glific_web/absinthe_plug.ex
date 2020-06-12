defmodule Glific.Absinthe.Plug do
  @moduledoc false

  defdelegate init(opts), to: Absinthe.Plug
  defdelegate call(conn, opts), to: Absinthe.Plug
end

defmodule Glific.Absinthe.Plug.GraphiQL do
  @moduledoc false

  defdelegate init(opts), to: Absinthe.Plug.GraphiQL
  defdelegate call(conn, opts), to: Absinthe.Plug.GraphiQL
end
