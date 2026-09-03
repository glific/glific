defmodule GlificWeb.Resolvers.MediaTest do
  use GlificWeb.ConnCase

  import Mock

  alias Glific.GCS.GcsWorker
  alias GlificWeb.Resolvers.Media

  @uploaded_url "https://gcs.test/logo.png"

  defp file_of(size_in_kb) do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}.png")
    File.write!(path, :binary.copy(<<0>>, size_in_kb * 1024))
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp upload(args, user) do
    Media.upload(nil, args, %{context: %{current_user: user}})
  end

  defp args(path, extras \\ %{}, organization_id) do
    Map.merge(
      %{media: %{path: path}, extension: "png", organization_id: organization_id},
      extras
    )
  end

  defp mocked_gcs(block) do
    with_mock GcsWorker, [:passthrough],
      upload_media: fn _local, _remote, _org -> {:ok, %{url: @uploaded_url, type: :image}} end do
      block.()
    end
  end

  describe "upload/3 size limit" do
    test "rejects a file larger than the caller's limit", %{
      user: user,
      organization_id: organization_id
    } do
      # No GCS mock: reaching the upload at all would fail this test, which is the point —
      # an oversized file must be refused before it is stored.
      assert {:error, message} =
               file_of(300) |> args(%{max_size_kb: 200}, organization_id) |> upload(user)

      assert message =~ "300KB"
      assert message =~ "limit is 200KB"
    end

    test "accepts a file within the limit", %{user: user, organization_id: organization_id} do
      mocked_gcs(fn ->
        assert {:ok, @uploaded_url} =
                 file_of(50) |> args(%{max_size_kb: 200}, organization_id) |> upload(user)
      end)
    end

    test "accepts a file exactly on the limit", %{user: user, organization_id: organization_id} do
      mocked_gcs(fn ->
        assert {:ok, @uploaded_url} =
                 file_of(200) |> args(%{max_size_kb: 200}, organization_id) |> upload(user)
      end)
    end

    test "imposes no limit when the caller does not ask for one", %{
      user: user,
      organization_id: organization_id
    } do
      # The chat composer uploads without a limit, so omitting it must behave exactly as before.
      mocked_gcs(fn ->
        assert {:ok, @uploaded_url} =
                 file_of(5000) |> args(organization_id) |> upload(user)
      end)
    end

    test "reports a file it cannot read rather than uploading it", %{
      user: user,
      organization_id: organization_id
    } do
      missing = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}.png")

      assert {:error, message} =
               args(missing, %{max_size_kb: 200}, organization_id) |> upload(user)

      assert message =~ "Could not read the uploaded file"
    end
  end
end
