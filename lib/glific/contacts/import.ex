defmodule Glific.Contacts.Import do
  @moduledoc """
  The Contact Importer Module
  """
  import Ecto.Query
  alias GlificWeb.Schema.Middleware.Authorize

  alias Glific.{
    Contacts,
    Contacts.BulkImportWorker,
    Contacts.Contact,
    Contacts.ContactHistory,
    Flows.ContactField,
    Groups,
    Groups.ContactGroup,
    Groups.GroupContacts,
    Jobs.UserJob,
    Notifications,
    Partners,
    Repo,
    Settings,
    Users.User
  }

  use Publicist

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

    contact_data_as_stream = fetch_contact_data_as_string(opts)

    contact_attrs = %{
      organization_id: organization_id,
      user: user,
      collection: collection,
      type: type
    }

    handle_csv_for_admins(contact_attrs, contact_data_as_stream, opts)
  end

  def import_contacts(organization_id, contact_attrs, opts) do
    if length(opts) > 1 do
      raise "Please specify only one of keyword arguments: file_path, url or data"
    end

    contact_data_as_stream = fetch_contact_data_as_string(opts)

    contact_attrs = %{
      organization_id: organization_id,
      user: contact_attrs.user,
      type: contact_attrs.type
    }

    handle_csv_for_admins(contact_attrs, contact_data_as_stream, opts)
  end

  @doc """
  Deletes/updates or add the given contact
  """
  @spec process_data(User.t() | map(), map(), map()) :: {:ok, map()} | {:error, map()}
  def process_data(user, %{delete: "1"} = contact, _attrs) do
    if Authorize.valid_role?(user.roles, :manager) || user.upload_contacts == true do
      case Repo.get_by(Contact, %{phone: contact.phone}) do
        nil ->
          {:error, %{contact.phone => "Contact does not exist"}}

        contact ->
          {:ok, contact} = Contacts.delete_contact(contact)
          {:ok, %{contact.phone => "Contact has been deleted as per flag in csv"}}
      end
    else
      {:error, %{contact.phone => "This user #{user.name} doesn't have enough permission"}}
    end
  end

  def process_data(user, contact_attrs, attrs) do
    case attrs.type do
      "import_contact" ->
        {:ok, contact} = Contacts.maybe_create_contact(contact_attrs)
        may_update_contact(contact_attrs)
        optin_contact(user, contact, contact_attrs)
        {:ok, %{contact.phone => "New contact has been created and marked as opted in"}}

      "move_contact" ->
        may_update_contact(contact_attrs)
    end
  end

  @doc "Validate a chunk of raw csv rows, returning the errors and the rows that parsed."
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

  @doc "Validate one csv row's phone number and name."
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

  @doc "Rebuild the worker params from the json serialized Oban args."
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

  @doc "Record one finished chunk against the user job, merging in any row level errors."
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
  defp merge_errors(existing, errors) when errors == %{}, do: existing || %{}

  defp merge_errors(existing, errors) do
    existing = existing || %{}
    Map.put(existing, "errors", Map.merge(Map.get(existing, "errors", %{}), errors))
  end

  @doc """
    Move the existing contacts to a group.
  """
  @spec add_contacts_to_group(integer, String.t(), [{atom(), String.t()}]) :: tuple()
  def add_contacts_to_group(organization_id, group_label, opts \\ []) do
    contact_data_as_stream = fetch_contact_data_as_string(opts)
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

  @spec add_contact_fields(Contact.t(), map()) :: {:ok, ContactGroup.t()}
  defp add_contact_fields(contact, fields) do
    Enum.reduce(fields, contact, fn {field, value}, contact ->
      field = Glific.string_snake_case(field)

      if value === "",
        do: contact,
        else:
          ContactField.do_add_contact_field(
            contact,
            field,
            field,
            value
          )
    end)
  end

  @spec fetch_contact_data_as_string(Keyword.t()) :: File.Stream.t() | IO.Stream.t()
  defp fetch_contact_data_as_string(opts) do
    file_path = Keyword.get(opts, :file_path, nil)
    url = Keyword.get(opts, :url, nil)
    data = Keyword.get(opts, :data, nil)

    cond do
      file_path != nil ->
        file_path |> Path.expand() |> File.stream!()

      url != nil ->
        {:ok, response} = Tesla.get(url)
        {:ok, stream} = StringIO.open(response.body)
        stream |> IO.binstream(:line)

      data != nil ->
        {:ok, stream} = StringIO.open(data)
        stream |> IO.binstream(:line)
    end
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

  @spec may_update_contact(map()) :: {:ok, any} | {:error, any}
  defp may_update_contact(contact_attrs) do
    with {:ok, old_contact} <- Repo.fetch_by(Contact, %{phone: contact_attrs.phone}),
         {:ok, contact} <- Contacts.maybe_update_contact(contact_attrs) do
      create_group_and_contact_fields(contact_attrs, contact)

      capture_language_history(
        contact,
        old_contact.language_id,
        contact_attrs.language_id
      )

      {:ok, %{contact.phone => "Contact has been updated"}}
    else
      {:error, error} when is_list(error) ->
        {:error, %{contact_attrs.phone => "Contact not found."}}

      {:error, %Ecto.Changeset{}} ->
        {:error, %{contact_attrs.phone => "Contact upload failed."}}
    end
  end

  @spec create_group_and_contact_fields(map(), Contact.t()) :: :ok | {:ok, ContactGroup.t()}
  defp create_group_and_contact_fields(contact_attrs, contact) do
    collection_label_check(contact, contact_attrs.collection)

    if contact_attrs[:contact_fields] not in [%{}] do
      add_contact_fields(contact, contact_attrs[:contact_fields])
    end
  end

  @spec collection_label_check(Contact.t(), String.t()) :: boolean() | :ok
  defp collection_label_check(_contact, nil), do: false

  defp collection_label_check(contact, collection) when is_binary(collection) do
    if String.length(collection) != 0 do
      collection = String.split(collection, ",")

      add_multiple_group(collection, contact.organization_id)
      add_contact_to_groups(collection, contact)
    end
  end

  @spec add_contact_to_groups(list(), Contact.t()) :: :ok
  defp add_contact_to_groups(collection, contact) do
    collection
    |> Groups.load_group_by_label()
    |> Enum.each(fn group ->
      Groups.create_contact_group(%{
        contact_id: contact.id,
        group_id: group.id,
        organization_id: contact.organization_id
      })
    end)
  end

  @spec add_multiple_group(list(), non_neg_integer()) :: :ok
  defp add_multiple_group(collection, organization_id) do
    collection
    |> Enum.each(fn label -> Groups.get_or_create_group_by_label(label, organization_id) end)
  end

  @spec optin_contact(User.t(), Contact.t(), map()) :: Contact.t()
  defp optin_contact(user, contact, contact_attrs) do
    current_time = DateTime.utc_now()

    if should_optin_contact?(user, contact) do
      contact_attrs
      |> Contacts.contact_opted_in(contact_attrs.organization_id, current_time, method: "Import")
      |> case do
        {:ok, contact} ->
          contact

        {:error, error} ->
          %{phone: contact.phone, error: "#{error}: #{contact.phone}"}
      end
    else
      %{
        phone: contact.phone,
        error:
          "Not able to optin the contact #{contact.phone}. Contact is either already opted in, opted out, or you lack permission"
      }
    end
  end

  ## later we can have one more column to say that force optin
  @spec should_optin_contact?(User.t(), Contact.t()) :: boolean()
  defp should_optin_contact?(user, contact) do
    cond do
      Map.get(contact, :optin_time) != nil ->
        false

      contact.optout_time != nil ->
        false

      Authorize.valid_role?(user.roles, :manager) || user.upload_contacts ->
        true

      true ->
        false
    end
  end

  @spec capture_language_history(
          Contact.t(),
          non_neg_integer() | String.t(),
          non_neg_integer() | String.t()
        ) ::
          {:ok, ContactHistory.t()} | {:error, Ecto.Changeset.t()} | nil
  defp capture_language_history(contact, old_language_id, language_id) do
    changed_language = Settings.get_language!(language_id)
    old_language = Settings.get_language!(old_language_id)

    if changed_language.id != old_language.id do
      Contacts.capture_history(contact, :contact_language_updated, %{
        event_label:
          "Changed contact language to #{changed_language.label} from #{old_language.label}, via import.",
        event_meta: %{
          language: %{
            id: changed_language.id,
            label: changed_language.label,
            old_language: old_language.id
          }
        }
      })
    end
  end
end
