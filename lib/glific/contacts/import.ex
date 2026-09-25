defmodule Glific.Contacts.Import do
  @moduledoc """
  The Contact Importer Module
  """
  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.BulkImportWorker,
    Contacts.Contact,
    CSV.Encoding,
    Groups,
    Groups.GroupContacts,
    Jobs.UserJob,
    Notifications,
    Partners,
    Repo
  }

  @contact_job_chunk_size 100

  @doc """
  This method allows importing of contacts to a particular organization and group

  The method takes in a csv file path and adds the contacts to the particular organization
  and group.
  """
  @spec import_contacts(non_neg_integer(), map(), [{atom(), String.t()}]) :: tuple()
  def import_contacts(
        organization_id,
        %{user: user, collection: collection, type: type} = _contact_attrs,
        opts
      ) do
    if length(opts) > 1 do
      raise "Please specify only one of keyword arguments: file_path, url or data"
    end

    contact_attrs = %{
      organization_id: organization_id,
      user: user,
      collection: collection,
      type: type
    }

    with {:ok, contact_data_as_stream} <- fetch_contact_data_as_string(opts) do
      handle_csv_for_admins(contact_attrs, contact_data_as_stream, opts)
    end
  end

  def import_contacts(organization_id, contact_attrs, opts) do
    if length(opts) > 1 do
      raise "Please specify only one of keyword arguments: file_path, url or data"
    end

    new_attrs = %{
      organization_id: organization_id,
      user: contact_attrs.user,
      type: contact_attrs.type
    }

    with {:ok, contact_data_as_stream} <- fetch_contact_data_as_string(opts) do
      handle_csv_for_admins(new_attrs, contact_data_as_stream, opts)
    end
  end

  @doc """
  Validate a chunk of raw csv rows, returning the errors and the rows that parsed.
  """
  @spec validate_contacts([map()]) :: {map(), [map()]}
  def validate_contacts(contacts) do
    {errors, valid} =
      Enum.reduce(contacts, {%{}, []}, fn contact, {errors, valid} ->
        case validate_contact(contact) do
          {:ok, clean_phone} -> {errors, [Map.put(contact, "phone", clean_phone) | valid]}
          {:error, error} -> {Map.merge(errors, error), valid}
        end
      end)

    # the accumulator prepends, so restore csv order: when a phone is listed twice it is
    # the later row that should win
    {errors, Enum.reverse(valid)}
  end

  @doc """
  Validate one csv row's phone number and name.
  """
  @spec validate_contact(map()) :: {:ok, String.t()} | {:error, map()}
  def validate_contact(%{"phone" => phone}) when phone in [nil, ""],
    do: {:error, %{"phone" => "Phone number is missing."}}

  def validate_contact(%{"phone" => phone, "name" => name}) do
    case Contacts.parse_phone_number(phone) do
      {:ok, clean_phone} -> validate_name(name, clean_phone)
      {:error, message} -> {:error, %{phone => message}}
    end
  end

  def validate_contact(_contact), do: {:error, %{"error" => "Failed to parse some rows"}}

  @spec validate_name(String.t() | nil, String.t()) :: {:ok, String.t()} | {:error, map()}
  defp validate_name(name, phone) when name in [nil, ""],
    do: {:error, %{phone => "Contact name is empty"}}

  defp validate_name(_name, phone), do: {:ok, phone}

  @doc """
  Rebuild the worker params from the json serialized Oban args.
  """
  @spec parse_worker_params(map(), non_neg_integer()) :: map()
  def parse_worker_params(params, organization_id) do
    %{
      organization_id: organization_id,
      type: params["type"],
      user: %{
        roles: Enum.map(params["user"]["roles"], &String.to_existing_atom/1),
        upload_contacts: params["user"]["upload_contacts"],
        name: params["user"]["name"]
      }
    }
  end

  @doc """
  Record one finished chunk against the user job, merging in any row level errors.
  """
  @spec update_user_job_progress(non_neg_integer(), map()) :: :ok
  def update_user_job_progress(user_job_id, errors) do
    Repo.transaction(fn ->
      user_job =
        UserJob
        |> lock("FOR UPDATE")
        |> Repo.get_by(id: user_job_id)

      UserJob.update_user_job(user_job, %{
        tasks_done: user_job.tasks_done + 1,
        errors: merge_errors(user_job.errors, errors)
      })
    end)

    :ok
  end

  @spec merge_errors(map() | nil, map()) :: map()
  defp merge_errors(existing, errors) when map_size(errors) == 0, do: existing || %{}

  defp merge_errors(existing, errors) do
    existing = existing || %{}
    Map.update(existing, "errors", errors, &Map.merge(&1, errors))
  end

  @doc """
    Move the existing contacts to a group.
  """
  @spec add_contacts_to_group(integer, String.t(), [{atom(), String.t()}]) :: tuple()
  def add_contacts_to_group(organization_id, group_label, opts \\ []) do
    with {:ok, contact_data_as_stream} <- fetch_contact_data_as_string(opts) do
      do_add_contacts_to_group(organization_id, group_label, contact_data_as_stream)
    end
  end

  @spec do_add_contacts_to_group(integer, String.t(), Enumerable.t()) :: tuple()
  defp do_add_contacts_to_group(organization_id, group_label, contact_data_as_stream) do
    {:ok, group} = Groups.get_or_create_group_by_label(group_label, organization_id)

    contact_id_list =
      contact_data_as_stream
      |> CSV.decode(headers: true, field_transform: &String.trim/1)
      |> Enum.map(fn {_, data} -> clean_contact_for_group(data, organization_id) end)
      |> get_contact_id_list(organization_id)

    %{
      group_id: group.id,
      add_contact_ids: contact_id_list,
      delete_contact_ids: [],
      organization_id: organization_id
    }
    |> GroupContacts.update_group_contacts()

    {:ok, %{message: "#{length(contact_id_list)} contacts added to group #{group_label}"}}
  end

  @doc """
  Fetches the contact upload report
  """
  @spec get_contact_upload_report(non_neg_integer(), map()) :: {:ok, any()}
  def get_contact_upload_report(organization_id, params) do
    Repo.put_process_state(organization_id)

    case UserJob.list_user_jobs(%{filter: %{id: params.user_job_id}}) do
      [%UserJob{status: "success"} = user_job] ->
        # Right now we only add the errors in the csv
        errors = user_job.errors["errors"] || %{}

        csv_rows =
          errors
          |> Enum.reduce("Phone,Status", fn {phone, status}, acc ->
            acc <> "\r\n#{phone},#{status}"
          end)

        {:ok, %{csv_rows: csv_rows}}

      [%UserJob{} = _user_job] ->
        {:ok, %{error: "Contact upload is in progress"}}

      [] ->
        {:ok, %{error: "Contact upload report doesn't exist"}}
    end
  end

  @spec clean_contact_for_group(map(), non_neg_integer()) :: map()
  defp clean_contact_for_group(data, _organization_id),
    do: %{phone: data["Contact Number"]}

  @spec get_contact_id_list(list(), non_neg_integer()) :: list()
  defp get_contact_id_list(contacts, org_id) do
    contact_phone_list = Enum.map(contacts, fn contact -> contact.phone end)
    Repo.put_organization_id(org_id)

    Contact
    |> where([c], c.organization_id == ^org_id)
    |> where([c], c.phone in ^contact_phone_list)
    |> select([c], c.id)
    |> Repo.all()
  end

  @spec cleanup_contact_data(map() | String.t(), map(), String.t()) :: map()
  defp cleanup_contact_data(%{"phone" => phone} = data, _contact_attrs, _date_format)
       when phone in ["", nil] do
    data
  end

  defp cleanup_contact_data(
         data,
         %{user: _user, organization_id: organization_id} = contact_attrs,
         _date_format
       )
       when is_map(data) do
    %{
      name: data["name"],
      phone: data["phone"],
      organization_id: organization_id,
      collection: get_collection(contact_attrs.type, data, contact_attrs),
      delete: data["delete"],
      language: data["language"],
      contact_fields: Map.drop(data, ["phone", "group", "language", "delete", "opt_in"])
    }
  end

  # Handling csv parsing errors for rows
  defp cleanup_contact_data(_data, _contact_attrs, _date_format) do
    %{}
  end

  defp get_collection(:import_contact, data, contact_attrs) do
    Map.get(contact_attrs, :collection, data["collection"])
  end

  defp get_collection(:move_contact, data, _contact_attrs) do
    data["collection"]
  end

  @spec fetch_contact_data_as_string(Keyword.t()) ::
          {:ok, Enumerable.t()} | {:error, map()}
  defp fetch_contact_data_as_string(opts) do
    file_path = Keyword.get(opts, :file_path, nil)
    url = Keyword.get(opts, :url, nil)
    data = Keyword.get(opts, :data, nil)

    cond do
      file_path != nil ->
        stream = file_path |> Path.expand() |> File.stream!()
        with :ok <- validate_encoding(stream), do: {:ok, Encoding.strip_bom(stream)}

      url != nil ->
        with {:ok, body} <- fetch_url(url), do: validated_string_stream(body)

      data != nil ->
        validated_string_stream(data)
    end
  end

  # Download the CSV rather than raising on a dead url, and reject a non-200 body instead of
  # parsing an error page as contacts.
  @spec fetch_url(String.t()) :: {:ok, binary()} | {:error, map()}
  defp fetch_url(url) do
    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      _ ->
        {:error,
         %{
           message: "Could not download the contacts CSV from the given URL.",
           details: "No contacts were imported."
         }}
    end
  end

  @spec validated_string_stream(binary()) :: {:ok, Enumerable.t()} | {:error, map()}
  defp validated_string_stream(contents) do
    with :ok <- validate_encoding(contents),
         do: {:ok, contents |> string_stream() |> Encoding.strip_bom()}
  end

  @spec validate_encoding(binary() | Enumerable.t()) :: :ok | {:error, map()}
  defp validate_encoding(contents) do
    case Encoding.validate(contents) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           message: reason,
           details: "No contacts were imported. The uploaded CSV is not valid UTF-8."
         }}
    end
  end

  @spec string_stream(binary()) :: IO.Stream.t()
  defp string_stream(contents) do
    {:ok, pid} = StringIO.open(contents)
    IO.binstream(pid, :line)
  end

  @spec handle_csv_for_admins(map(), map(), [{atom(), String.t()}]) :: list() | {:error, any()}
  defp handle_csv_for_admins(contact_attrs, data, opts) do
    # this ensures the  org_id exists and is valid
    case Partners.organization(contact_attrs.organization_id) do
      %{} ->
        decode_csv_data(contact_attrs, data, opts)

      {:error, error} ->
        {:error,
         %{
           message: "All contacts could not be added",
           details:
             "Could not fetch the organization with id #{contact_attrs.organization_id}. Error -> #{Glific.SafeLog.safe_inspect(error)}"
         }}
    end
  end

  @spec decode_csv_data(map(), map(), [{atom(), String.t()}]) :: {:ok, map()}
  defp decode_csv_data(params, data, opts) do
    %{organization_id: organization_id, user: _user} = params
    {date_format, _opts} = Keyword.pop(opts, :date_format, "{YYYY}-{M}-{D} {h24}:{m}:{s}")

    user_job_attrs = %{
      status: "pending",
      type: "contact_import",
      total_tasks: 0,
      tasks_done: 0,
      organization_id: organization_id,
      errors: %{}
    }

    user_job = UserJob.create_user_job(user_job_attrs)
    create_contact_upload_notification(organization_id, user_job.id)
    Glific.Metrics.increment("Contact Job Created")

    params = %{
      params
      | user: %{roles: params.user.roles, upload_contacts: params.user.upload_contacts}
    }

    total_chunks =
      data
      |> CSV.decode(headers: true, field_transform: &String.trim/1)
      |> Stream.map(fn {_, data} -> cleanup_contact_data(data, params, date_format) end)
      |> Stream.chunk_every(@contact_job_chunk_size)
      |> Stream.with_index()
      |> Enum.map(fn {chunk, index} ->
        BulkImportWorker.make_job(chunk, params, user_job.id, index * 2)
      end)
      |> Enum.count()

    UserJob.update_user_job(user_job, %{total_tasks: total_chunks, all_tasks_created: true})
    {:ok, %{status: "Contact import is in progress"}}
  end

  @spec create_contact_upload_notification(integer(), integer()) :: :ok
  defp create_contact_upload_notification(organization_id, user_job_id) do
    Notifications.create_notification(%{
      category: "Contact Upload",
      message: "Contact upload in progress",
      severity: Notifications.types().info,
      organization_id: organization_id,
      entity: %{user_job_id: user_job_id}
    })

    :ok
  end
end
