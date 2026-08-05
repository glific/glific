defmodule Glific.Providers.Web.UploadTest do
  use Glific.DataCase

  alias Glific.Providers.Web.Upload

  describe "upload_file/4" do
    setup do
      source_path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}.png")
      File.write!(source_path, "fake image bytes")

      on_exit(fn -> File.rm(source_path) end)

      %{source_path: source_path}
    end

    test "writes the file under priv/static/uploads and returns its hosted url", %{
      organization_id: organization_id,
      source_path: source_path
    } do
      assert {:ok, %{url: url, content_type: "image/png"}} =
               Upload.upload_file(organization_id, source_path, "png", "image/png")

      assert url =~ "/uploads/#{organization_id}/"

      relative_path =
        url
        |> String.split("/uploads/")
        |> List.last()

      written_path =
        Path.join([Application.app_dir(:glific, "priv/static/uploads"), relative_path])

      assert File.exists?(written_path)

      on_exit(fn -> File.rm(written_path) end)
    end

    test "returns an error when neither GCS nor local media is available", %{
      organization_id: organization_id,
      source_path: source_path
    } do
      previous_value = Application.get_env(:glific, :web_channel_local_media)
      Application.put_env(:glific, :web_channel_local_media, false)

      on_exit(fn ->
        Application.put_env(:glific, :web_channel_local_media, previous_value)
      end)

      assert {:error, reason} =
               Upload.upload_file(organization_id, source_path, "png", "image/png")

      assert reason =~ "media upload unavailable"
    end
  end
end
