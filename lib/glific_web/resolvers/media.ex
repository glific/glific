defmodule GlificWeb.Resolvers.Media do
  @moduledoc """
  Resolver to deal with file uploads, which we send directly to GCS
  """
  alias Glific.{GCS.GcsWorker, Partners.Saas, Users.User}

  @doc """
  Upload a file given its extension.

  A caller that knows what it is uploading may cap the size with `max_size_kb`. The client
  checks too, so this is the backstop for a request that did not come from our form — the only
  other bound is `Plug.Parsers`, which admits 20MB.

  It may also name a `folder`, which files the object under `<folder>/<org id>/<uuid>.<ext>`
  rather than the default message-attachment path. The organisation id is taken from the
  request, never from the caller, so one org cannot write into another's prefix.

  `storage: :saas` writes to the platform organisation's bucket instead of the uploading
  organisation's, the same way global stats are stored under the SaaS org's credentials. That
  is what lets an organisation with no Google Cloud Storage of its own still upload — without
  it, a missing GCS credential would block the feature entirely.
  """
  @spec upload(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload(
        _,
        %{media: media, extension: extension, organization_id: organization_id} = args,
        %{context: %{current_user: user}}
      ) do
    with :ok <- within_size_limit(media.path, args[:max_size_kb]),
         {:ok, remote} <- remote_path(args[:folder], user, extension, organization_id) do
      media.path
      |> GcsWorker.upload_media(remote, storage_organization_id(args[:storage], organization_id))
      |> handle_response()
    end
  end

  # Both the bucket and the service account are resolved from whichever organisation is passed
  # to GcsWorker, so this one value chooses the account. The path keeps the *uploading* org's
  # id either way, so an object stays attributable in a shared bucket.
  @spec storage_organization_id(atom() | nil, non_neg_integer()) :: non_neg_integer()
  defp storage_organization_id(:saas, _organization_id), do: Saas.organization_id()
  defp storage_organization_id(_storage, organization_id), do: organization_id

  # Anchored, and with no "." allowed, so a folder can never climb out of its prefix.
  @folder_format ~r{^[a-z0-9][a-z0-9_-]*(/[a-z0-9][a-z0-9_-]*)*$}

  @spec remote_path(String.t() | nil, User.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp remote_path(nil, user, extension, _organization_id),
    do: {:ok, remote_name(user, extension)}

  defp remote_path(folder, _user, extension, organization_id) do
    if Regex.match?(@folder_format, folder),
      do: {:ok, "#{folder}/#{organization_id}/#{Ecto.UUID.generate()}.#{extension}"},
      else: {:error, "folder may only contain lowercase letters, digits, dashes and slashes."}
  end

  @spec within_size_limit(String.t(), integer() | nil) :: :ok | {:error, String.t()}
  defp within_size_limit(_path, nil), do: :ok

  # Absinthe's :integer is signed, and a negative limit would reject every upload — the
  # comparison below is true for any size. Refuse the argument rather than the file.
  defp within_size_limit(_path, max_size_kb) when max_size_kb <= 0,
    do: {:error, "max_size_kb must be greater than zero."}

  defp within_size_limit(path, max_size_kb) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > max_size_kb * 1024 ->
        {:error, "File is #{div(size, 1024)}KB. The limit is #{max_size_kb}KB."}

      {:ok, _stat} ->
        :ok

      {:error, reason} ->
        {:error, "Could not read the uploaded file: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Upload a blob encoded in base64 given its extension
  """
  @spec upload_blob(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_blob(
        _,
        %{media: media, extension: extension, organization_id: organization_id},
        %{context: %{current_user: user}}
      ) do
    uuid = Ecto.UUID.generate()

    # first decode blob and store in temp file
    local_file = local_name(extension, uuid)

    File.write!(
      local_file,
      Base.decode64!(media)
    )

    GcsWorker.upload_media(local_file, remote_name(user, extension, uuid), organization_id)
    |> handle_response()
  end

  @spec local_name(String.t(), Ecto.UUID.t()) :: String.t()
  defp local_name(extension, uuid),
    do: "#{System.tmp_dir!()}/#{uuid}.#{extension}"

  @spec remote_name(User.t(), String.t(), Ecto.UUID.t() | nil) :: String.t()
  defp remote_name(user, extension, uuid \\ Ecto.UUID.generate()) do
    {year, week} = Timex.iso_week(Timex.now())
    "outbound/#{year}-#{week}/#{user.name}/#{uuid}.#{extension}"
  end

  @spec handle_response(any()) :: {:ok, String.t()} | {:error, String.t()}
  defp handle_response(response) do
    response
    |> case do
      {:ok, %{url: url} = _} -> {:ok, url}
      error -> {:error, "Something went wrong #{Glific.SafeLog.safe_inspect(error)}"}
    end
  end
end
