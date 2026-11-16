defmodule Glific.DnsResolverStub do
  @moduledoc """
  Offline stand-in for `:inet.getaddrs/2`, so tests that import from a URL never do a real DNS
  lookup. `localhost` and `internal.example` resolve to internal addresses; every other host
  resolves to a public one.
  """

  @doc "Resolves `host` to fixed addresses without touching the network."
  @spec getaddrs(charlist(), :inet | :inet6) :: {:ok, [:inet.ip_address()]} | {:error, atom()}
  def getaddrs(~c"localhost", :inet), do: {:ok, [{127, 0, 0, 1}]}
  def getaddrs(~c"internal.example", :inet), do: {:ok, [{10, 0, 0, 1}]}
  def getaddrs(_host, :inet), do: {:ok, [{93, 184, 216, 34}]}
  def getaddrs(_host, :inet6), do: {:error, :nxdomain}
end
