defmodule Glific.Contacts.Import do
  @moduledoc """
  The Contact Importer Module
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.ContactField,
    Groups,
    Groups.ContactGroup,
    Groups.GroupContacts,
    Partners,
    Repo,
    Settings,
    Users.User
  }

  @max_concurrency System.schedulers_online()

  @spec cleanup_contact_data(map(), map(), String.t()) :: map()
  defp cleanup_contact_data(
         data,
         %{user: user, organization_id: organization_id} = contact_attrs,
         date_format
       ) do
    results =
      %{
        name: data["name"],
        phone: data["phone"],
        organization_id: organization_id,
        collection: data["collection"],
        delete: data["delete"],
        contact_fields: Map.drop(data, ["phone", "group", "language", "delete", "opt_in"])
      }
      |> add_language(data["language"])
      |> add_optin_date(data["opt_in"], date_format)

    cond do
      user.roles == [:glific_admin] ->
        results
        |> Map.merge(%{
          delete: data["delete"],
          collection: Map.get(contact_attrs, :collection, data["collection"])
        })

      user.upload_contacts ->
        results
        |> Map.merge(%{
          delete: data["delete"]
        })

      true ->
        results
    end
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

  @doc """
  This method allows importing of contacts to a particular organization and group

  The method takes in a csv file path and adds the contacts to the particular organization
  and group.
  """
  @spec import_contacts(non_neg_integer(), map(), [{atom(), String.t()}]) :: tuple()
  def import_contacts(
        organization_id,
        %{user: user, collection: collection} = _contact_attrs,
        opts
      ) do
    if length(opts) > 1 do
      raise "Please specify only one of keyword arguments: file_path, url or data"
    end

    contact_data_as_stream = fetch_contact_data_as_string(opts)
    contact_attrs = %{organization_id: organization_id, user: user, collection: collection}
    handle_csv_for_admins(contact_attrs, contact_data_as_stream, opts)
  end

  def import_contacts(organization_id, contact_attrs, opts) do
    if length(opts) > 1 do
      raise "Please specify only one of keyword arguments: file_path, url or data"
    end

    contact_data_as_stream = fetch_contact_data_as_string(opts)
    contact_attrs = %{organization_id: organization_id, user: contact_attrs.user}
    handle_csv_for_admins(contact_attrs, contact_data_as_stream, opts)
  end

  @spec handle_csv_for_admins(map(), map(), [{atom(), String.t()}]) :: tuple()
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
             "Could not fetch the organization with id #{contact_attrs.organization_id}. Error -> #{inspect(error)}"
         }}
    end
  end

  @spec decode_csv_data(map(), map(), [{atom(), String.t()}]) :: tuple()
  defp decode_csv_data(params, data, opts) do
    %{organization_id: organization_id, user: user} = params
    {date_format, _opts} = Keyword.pop(opts, :date_format, "{YYYY}-{M}-{D} {h24}:{m}:{s}")

    result =
      data
      |> CSV.decode(headers: true, strip_fields: true)
      |> Stream.map(fn {_, data} -> cleanup_contact_data(data, params, date_format) end)
      |> Task.async_stream(
        fn contact ->
          process_data(user, contact, %{
            organization_id: Repo.put_process_state(organization_id)
          })
        end,
        max_concurrency: @max_concurrency
      )
      |> Enum.map(fn {:ok, result} -> result end)

    csv_rows =
      result
      |> Enum.reduce("Phone,Status", fn {phone, status}, acc ->
        acc <> "\r\n#{phone},#{status}"
      end)

    {:ok, %{csv_rows: csv_rows}}
  end

  @spec process_data(User.t(), map(), map()) :: Contact.t() | map()
  defp process_data(user, %{delete: "1"} = contact, _contact_attrs) do
    if user.roles == [:glific_admin] || user.upload_contacts == true do
      case Repo.get_by(Contact, %{phone: contact.phone}) do
        nil ->
          %{ok: "Contact does not exist"}

        contact ->
          {:ok, contact} = Contacts.delete_contact(contact)
          contact
      end
    else
      %{
        error: "This user doesn't have enough permission"
      }
    end
  end

  defp process_data(user, contact_attrs, _attrs) do
    cond do
      user.roles == [:glific_admin] ->
        {:ok, contact} = Contacts.maybe_create_contact(contact_attrs)

        create_group_and_contact_fields(contact_attrs, contact)
        optin_contact(user, contact, contact_attrs)

      user.upload_contacts ->
        {:ok, contact} = Contacts.maybe_create_contact(contact_attrs)
        may_update_contact(contact_attrs)
        optin_contact(user, contact, contact_attrs)

      true ->
        may_update_contact(contact_attrs)
    end
  end

  @spec may_update_contact(map()) :: {:ok, any} | {:error, any}
  defp may_update_contact(contact_attrs) do
    case Contacts.maybe_update_contact(contact_attrs) do
      {:ok, contact} ->
        create_group_and_contact_fields(contact_attrs, contact)
        {contact.phone, "Contact has been updated"}

      {:error, error} ->
        Map.put(%{}, contact_attrs.phone, "#{error}")
        {contact_attrs.phone, "#{error}"}
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
    if should_optin_contact?(user, contact, contact_attrs) do
      contact_attrs
      |> Map.put(:method, "Import")
      |> Contacts.optin_contact()
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
          "Not able to optin the contact #{contact.phone}. Either the contact is opted out, invalid or the opted-in time present in sheet is not in the correct format"
      }
    end
  end

  ## later we can have one more column to say that force optin
  @spec should_optin_contact?(User.t(), Contact.t(), map()) :: boolean()
  defp should_optin_contact?(user, contact, attrs) do
    cond do
      Map.get(attrs, :optin_time, nil) == nil ->
        false

      contact.optout_time != nil ->
        false

      user.roles == [:glific_admin] || user.upload_contacts ->
        true

      true ->
        false
    end
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
      |> CSV.decode(headers: true, strip_fields: true)
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

  @spec add_language(map(), nil) :: map()
  defp add_language(results, nil), do: results

  defp add_language(results, language) do
    Map.put(
      results,
      :language_id,
      Enum.at(Settings.get_language_by_label_or_locale(language), 0).id
    )
  end

  @spec add_optin_date(map(), any(), String.t()) :: map()
  defp add_optin_date(results, "", _date_format), do: Map.put(results, :optin, nil)
  defp add_optin_date(results, nil, _date_format), do: results

  defp add_optin_date(results, opt_in, date_format) do
    Map.put(
      results,
      :optin_time,
      elem(Timex.parse(opt_in, date_format), 1)
    )
  end
end
