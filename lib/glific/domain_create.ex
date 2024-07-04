defmodule Glific.DomainCreate do
  @moduledoc """
  This module adds domains via Gigalixir API using the Tesla module.
  """

  @endpoint "https://api.gigalixir.com/api/apps/glific-staging/domains"
  @username "vgull574@stanford.edu"
  @api_key "4f91902b-6d0f-4068-9f76-2c7916ff0b79"

  use Tesla

  plug Tesla.Middleware.BaseUrl, @endpoint
  plug Tesla.Middleware.Headers, [{"Content-Type", "application/json"}]
  plug Tesla.Middleware.BasicAuth, username: @username, password: @api_key

  @spec create_domain(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create_domain(domain) do
    body = %{"fqdn" => domain}

    case post("/", Jason.encode!(body)) do
      {:ok, %Tesla.Env{status: 201}} ->
        {:ok, "Domain successfully created!"}

      {:ok, %Tesla.Env{status: status, body: response_body}} when status >= 400 ->
        {:error, "Failed with status #{status}: #{response_body}"}

      {:error, err} ->
        {:error, "Request failed: #{inspect(err)}"}

    end
  end
end
