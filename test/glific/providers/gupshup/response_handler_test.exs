defmodule Glific.Providers.Gupshup.ResponseHandlerTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Messages.Message,
    Providers.Gupshup.ResponseHandler,
    Repo
  }

  # Mirror the worker: the send-time message is the Oban-serialised minimal map
  # (string keys), built from a persisted message so the success/error handlers
  # have a row to update.
  defp send_message(attrs \\ %{}) do
    Fixtures.message_fixture(Map.merge(%{flow: :outbound}, attrs))
    |> Message.to_minimal_map()
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp reload(message), do: Repo.get!(Message, message["id"])

  describe "handle_response/2 — Tesla responses" do
    test "2xx marks the message enqueued (success send)" do
      message = send_message()

      body = Jason.encode!(%{"status" => "submitted", "messageId" => "gupshup-success-id"})

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 200, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :enqueued
      assert reloaded.bsp_message_id == "gupshup-success-id"
    end

    test "4xx marks the message errored and is not retried (returns :ok)" do
      message = send_message(%{is_hsm: true})

      body =
        Jason.encode!(%{"status" => "error", "code" => 131_049, "message" => "frequency capped"})

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 400, body: body}},
                 message
               )

      assert reload(message).bsp_status == :error
    end

    test "5xx returns an error tuple so Oban retries" do
      message = send_message()
      body = Jason.encode!(%{"status" => "error"})

      assert {:error, _body} =
               ResponseHandler.handle_response(
                 {:ok, %Tesla.Env{status: 500, body: body}},
                 message
               )
    end
  end

  describe "handle_response/2 — Req responses (V3 API)" do
    test "2xx stores the message id from messages[0].id" do
      message = send_message(%{is_hsm: true})

      body = %{"messages" => [%{"id" => "gupshup-v3-id"}], "messaging_product" => "whatsapp"}

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Req.Response{status: 200, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :enqueued
      assert reloaded.bsp_message_id == "gupshup-v3-id"
    end

    test "4xx marks the message errored and is not retried (returns :ok)" do
      message = send_message(%{is_hsm: true})

      body = %{"error" => %{"code" => 132_000, "message" => "Param count mismatch"}}

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Req.Response{status: 400, body: body}},
                 message
               )

      reloaded = reload(message)
      assert reloaded.bsp_status == :error
      assert reloaded.errors == body
    end

    test "4xx with a plain text body still marks the message errored" do
      message = send_message(%{is_hsm: true})

      assert :ok =
               ResponseHandler.handle_response(
                 {:ok, %Req.Response{status: 401, body: "Unauthorized"}},
                 message
               )

      assert reload(message).bsp_status == :error
    end
  end

  describe "handle_response/2 — transport errors" do
    test "a timeout returns an error tuple so Oban retries" do
      message = send_message()

      assert {:error, _body} = ResponseHandler.handle_response({:error, :timeout}, message)
      assert reload(message).bsp_status == :error
    end

    test "a non-timeout transport error is swallowed (returns :ok)" do
      message = send_message()

      assert :ok = ResponseHandler.handle_response({:error, :econnrefused}, message)
      assert reload(message).bsp_status == :error
    end
  end
end
