defmodule Glific.Gigalixir do
  @moduledoc """
  This Module contains functions that communicate with Gigalixir via Gigalixir API
  """

  @base_url "https://api.gigalixir.com/api/apps"

  use Tesla
  require Logger

  plug Tesla.Middleware.BaseUrl,
       "#{@base_url}/#{Application.get_env(:glific, :gigalixir_app_name)}/domains"

  plug Tesla.Middleware.Headers, [{"Content-Type", "application/json"}]

  plug Tesla.Middleware.BasicAuth,
    username: Application.get_env(:glific, :gigalixir_username),
    password: Application.get_env(:glific, :gigalixir_api_key)

  @doc """
  "Add a domain via Gigalixir API with NGO shortcode
  """
  @spec create_domain(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create_domain(shortcode) do
    domain = "#{shortcode}.glific.com"
    body = %{"fqdn" => domain}

    case post("/", Jason.encode!(body)) do
      {:ok, %Tesla.Env{status: 201}} ->
        {:ok, "Domain successfully created!"}

      {:ok, %Tesla.Env{status: status, body: response_body}} when status >= 400 ->
        Logger.error("Failed with status: '#{status}': #{inspect(response_body)}")
        {:error, "Failed with status #{status}: #{inspect(response_body)}"}

      {:error, err} ->
        Logger.error("Request failed: #{inspect(err)}")
        {:error, "Request failed: #{inspect(err)}"}
    end
  end
end
