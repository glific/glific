defmodule Glific.Providers.ResponseHandler do
  @moduledoc """
  Module for handling response from Provider end
  or Handle response for simulators
  """
  alias Glific.{
    Communications,
    Messages.Message
  }

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t()) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        Communications.Message.handle_success_response(response, message)
        :ok

      # Not authorized, Job succeeded, we should return an ok, so we dont retry
      %Tesla.Env{status: status} when status in 400..499 ->
        Communications.Message.handle_error_response(response, message)
        :ok

      _ ->
        Communications.Message.handle_error_response(response, message)
    end
  end

  @spec handle_fake_response(Message.t(), String.t(), non_neg_integer) ::
          :ok | {:error, String.t()}
  def handle_fake_response(message, body, status) do
    {:ok,
     %Tesla.Env{
       __client__: %Tesla.Client{adapter: nil, fun: nil, post: [], pre: []},
       __module__: Glific.Providers.Gupshup.ApiClient,
       body: body,
       method: :post,
       status: status
     }}
    |> handle_response(message)
  end
end
