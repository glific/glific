defmodule Glific.URI do
  @moduledoc """
  This file has been copied (and modified a wee bit)from
  https://github.com/jerel/ecto_fields/blob/master/lib/fields/url.ex

  The ownership, author and license (MIT) remains with the original owner of that repository
  """
  @spec type :: :string
  def type, do: :string

  @doc """
  Validate that the given value is a valid fully qualified url

  ## Examples

      iex> EctoFields.URL.cast("http://1.1.1.1")
      :ok

      iex> EctoFields.URL.cast("http://example.com")
      :ok

      iex> EctoFields.URL.cast("https://example.com")
      :ok

      iex> EctoFields.URL.cast("http://example.com/test/foo.html?search=1&page=two#header")
      :ok

      iex> EctoFields.URL.cast("http://example.com:8080/")
      :ok

      iex> EctoFields.URL.cast("myblog.html")
      :error

      iex> EctoFields.URL.cast("http://example.com\blog\first")
      :error
  """
  @spec cast(String.t()) :: :ok | :error
  def cast(url) when is_binary(url) and byte_size(url) > 0 do
    url
    |> validate_protocol
    |> validate_host
    |> validate_uri
  end

  def cast(nil), do: :ok

  def cast(_), do: :error

  defp validate_protocol("http://" <> rest = url) do
    {url, rest}
  end

  defp validate_protocol("https://" <> rest = url) do
    {url, rest}
  end

  defp validate_protocol(_), do: :error

  defp validate_host(:error), do: :error

  defp validate_host({url, rest}) do
    [domain | uri] = String.split(rest, "/")

    domain =
      case String.split(domain, ":") do
        # ipv6
        [_, _, _, _, _, _, _, _] -> domain
        [domain, _port] -> domain
        _ -> domain
      end

    erl_host = String.to_charlist(domain)

    if :inet_parse.domain(erl_host) or
         match?({:ok, _}, :inet_parse.ipv4strict_address(erl_host)) or
         match?({:ok, _}, :inet_parse.ipv6strict_address(erl_host)) do
      {url, Enum.join(uri, "/")}
    else
      :error
    end
  end

  defp validate_uri(:error), do: :error

  defp validate_uri({_url, uri}) do
    if uri == URI.encode(uri) |> URI.decode(),
      do: :ok,
      else: :error
  end
end
