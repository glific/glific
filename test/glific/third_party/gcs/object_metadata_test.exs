defmodule Glific.GCS.ObjectMetadataTest do
  @moduledoc false
  use Glific.DataCase

  alias Glific.GCS.ObjectMetadata

  describe "fetch/2" do
    test "returns the object's size and content type" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        assert url == "https://storage.googleapis.com/storage/v1/b/some-bucket/o/some-object.png"

        %Tesla.Env{
          status: 200,
          body: %{"size" => "12345", "contentType" => "image/png"}
        }
      end)

      assert {:ok, %{size: 12_345, content_type: "image/png"}} =
               ObjectMetadata.fetch("some-bucket", "some-object.png")
    end

    test "percent-encodes the object name in the request path" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        assert url ==
                 "https://storage.googleapis.com/storage/v1/b/some-bucket/o/nested%2Fobject.png"

        %Tesla.Env{status: 200, body: %{"size" => "1", "contentType" => "image/png"}}
      end)

      assert {:ok, _metadata} = ObjectMetadata.fetch("some-bucket", "nested/object.png")
    end

    test "returns an error when the object does not exist" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 404, body: %{"error" => %{"message" => "Not Found"}}}
      end)

      assert {:error, {:http_status, 404}} = ObjectMetadata.fetch("some-bucket", "missing.png")
    end

    test "returns an error on an unparseable response" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{"unexpected" => "shape"}}
      end)

      assert {:error, :invalid_response} = ObjectMetadata.fetch("some-bucket", "some-object.png")
    end

    test "returns an error on a network failure" do
      Tesla.Mock.mock(fn %{method: :get} -> {:error, :timeout} end)

      assert {:error, :timeout} = ObjectMetadata.fetch("some-bucket", "some-object.png")
    end
  end
end
