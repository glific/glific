defmodule Glific.Providers.Web.Upload do
  @moduledoc """
  Turns a file a browser contact uploaded over the web channel into a hosted URL.

  The web-channel end user is not a staff `Glific.Users.User`, so it cannot use the
  `:staff`-gated `uploadMedia` GraphQL mutation. This module offers the same underlying
  Google Cloud Storage upload (`Glific.GCS.GcsWorker.upload_media/3`) behind a
  contact-facing entry point.

  When the organization has no GCS credential and the dev/test-only
  `:web_channel_local_media` flag is enabled, the file is instead written under
  `priv/static/uploads/<org_id>/` and served by the endpoint's `Plug.Static`, so media
  round-trips locally without any cloud configuration. That fallback is never enabled in
  production.
  """

  alias Glific.{GCS.GcsWorker, Partners}

  @doc """
  Upload a local file for the given organization, returning its hosted URL and content type.

  `local_path` is a file already on disk (e.g. a `%Plug.Upload{}.path`). Prefers GCS when the
  org has it configured, otherwise falls back to local disk when `:web_channel_local_media` is
  enabled, otherwise returns an error.
  """
  @spec upload_file(non_neg_integer(), String.t(), String.t(), String.t() | nil) ::
          {:ok, %{url: String.t(), content_type: String.t() | nil}} | {:error, String.t()}
  def upload_file(organization_id, local_path, extension, content_type) do
    cond do
      Partners.attachments_enabled?(organization_id) ->
        gcs_upload(organization_id, local_path, extension, content_type)

      local_media_enabled?() ->
        local_upload(organization_id, local_path, extension, content_type)

      true ->
        {:error, "media upload unavailable: configure Google Cloud Storage"}
    end
  end

  @spec gcs_upload(non_neg_integer(), String.t(), String.t(), String.t() | nil) ::
          {:ok, %{url: String.t(), content_type: String.t() | nil}} | {:error, String.t()}
  defp gcs_upload(organization_id, local_path, extension, content_type) do
    case GcsWorker.upload_media(local_path, remote_name(extension), organization_id) do
      {:ok, %{url: url}} -> {:ok, %{url: url, content_type: content_type}}
      error -> {:error, "media upload failed: #{Glific.SafeLog.safe_inspect(error)}"}
    end
  end

  @spec local_upload(non_neg_integer(), String.t(), String.t(), String.t() | nil) ::
          {:ok, %{url: String.t(), content_type: String.t() | nil}} | {:error, String.t()}
  defp local_upload(organization_id, local_path, extension, content_type) do
    filename = "#{Ecto.UUID.generate()}.#{extension}"
    dir = Path.join(local_media_dir(), to_string(organization_id))
    File.mkdir_p!(dir)
    File.cp!(local_path, Path.join(dir, filename))

    url = "#{GlificWeb.Endpoint.url()}/uploads/#{organization_id}/#{filename}"
    {:ok, %{url: url, content_type: content_type}}
  end

  @spec remote_name(String.t()) :: String.t()
  defp remote_name(extension) do
    {year, week} = Timex.iso_week(Timex.now())
    "outbound/#{year}-#{week}/web_channel/#{Ecto.UUID.generate()}.#{extension}"
  end

  @spec local_media_enabled?() :: boolean()
  defp local_media_enabled?, do: Application.get_env(:glific, :web_channel_local_media, false)

  @spec local_media_dir() :: String.t()
  defp local_media_dir, do: Application.app_dir(:glific, "priv/static/uploads")
end
