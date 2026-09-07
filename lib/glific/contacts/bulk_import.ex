defmodule Glific.Contacts.BulkImport do
  @moduledoc """
  Batched contact import.

  Processes a whole chunk of CSV rows with a fixed number of SQL statements, rather than
  one write per contact field. The previous path issued six to nine statements for every
  field of every contact — an `UPDATE contacts`, a `contacts_fields` lookup, a
  `contact_histories` insert and the two row triggers that insert fires — which row-locked
  the contacts table for the duration of an import.

  Everything here is expressed as a batch: one lookup of the existing contacts, one upsert,
  one field-registry upsert, one history insert and one collection insert per chunk.
  """
  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactHistory,
    Contacts.ContactsField,
    Contacts.Import,
    Groups,
    Groups.ContactGroup,
    Profiles,
    Repo,
    Settings.Language
  }

  alias GlificWeb.Schema.Middleware.Authorize

  @default_language "english"
  @field_type "string"

  @doc """
  Import one chunk of csv rows, returning a map of phone => error message.
  """
  @spec process_chunk([map()], map()) :: map()
  def process_chunk(rows, params) do
    {errors, rows} = Import.validate_contacts(rows)
    {deletes, rows} = Enum.split_with(rows, &(&1["delete"] == "1"))

    existing = load_existing(rows)
    {errors, rows} = reject_missing(rows, existing, errors, params.type)

    languages = language_index()
    params = Map.put(params, :language_labels, languages.labels)
    now = DateTime.utc_now()

    prepared =
      rows
      |> Enum.map(&prepare(&1, existing, languages, params, now))
      |> dedupe()

    {:ok, _} = Repo.transaction(fn -> write(prepared, params, now) end)

    delete_errors = Enum.reduce(deletes, %{}, &delete_contact(&1, params, &2))

    Map.merge(errors, delete_errors)
  end

  # one transaction so a chunk that dies half way cannot leave the history rows behind:
  # the contact, field and collection writes are idempotent on retry, the history insert
  # is not. The user job progress deliberately stays outside this, since it takes a
  # FOR UPDATE lock on a single row that every worker shares.
  @spec write([map()], map(), DateTime.t()) :: :ok
  defp write(prepared, params, now) do
    saved = upsert_contacts(prepared, params, now)

    upsert_field_registry(prepared, params, now)
    insert_histories(prepared, saved, params, now)
    link_collections(prepared, saved, params, now)
    sync_profiles(prepared, saved, now)
  end

  @spec load_existing([map()]) :: map()
  defp load_existing([]), do: %{}

  defp load_existing(rows) do
    phones = Enum.map(rows, & &1["phone"])

    Contact
    |> where([c], c.phone in ^phones)
    |> select([c], %{
      id: c.id,
      phone: c.phone,
      language_id: c.language_id,
      optin_time: c.optin_time,
      optout_time: c.optout_time,
      last_message_at: c.last_message_at,
      fields: c.fields,
      status: c.status,
      active_profile_id: c.active_profile_id
    })
    |> Repo.all()
    |> Map.new(&{&1.phone, &1})
  end

  @spec reject_missing([map()], map(), map(), String.t()) :: {map(), [map()]}
  defp reject_missing(rows, existing, errors, "move_contact") do
    {errors, keep} =
      Enum.reduce(rows, {errors, []}, fn row, {errors, keep} ->
        phone = row["phone"]

        if Map.has_key?(existing, phone),
          do: {errors, [row | keep]},
          else:
            {Map.put(errors, phone, "Contact #{phone} was not found and hence not added"), keep}
      end)

    {errors, Enum.reverse(keep)}
  end

  defp reject_missing(rows, _existing, errors, _type), do: {errors, rows}

  @spec language_index() :: map()
  defp language_index do
    languages =
      Language
      |> where([l], l.is_active == true)
      |> order_by([l], asc: l.id)
      |> select([l], %{id: l.id, label: l.label, locale: l.locale})
      |> Repo.all(skip_organization_id: true)

    lookup =
      Enum.reduce(languages, %{}, fn language, acc ->
        acc
        |> put_new_downcased(language.label, language.id)
        |> put_new_downcased(language.locale, language.id)
      end)

    default_id =
      Map.get(lookup, @default_language) ||
        raise "contact import needs an active #{@default_language} language to fall back on"

    %{
      lookup: lookup,
      ordered: Enum.sort_by(lookup, fn {key, id} -> {id, key} end),
      labels: Map.new(languages, &{&1.id, &1.label}),
      default_id: default_id
    }
  end

  @spec put_new_downcased(map(), String.t() | nil, non_neg_integer()) :: map()
  defp put_new_downcased(acc, nil, _id), do: acc
  defp put_new_downcased(acc, key, id), do: Map.put_new(acc, String.downcase(key), id)

  @spec prepare(map(), map(), map(), map(), DateTime.t()) :: map()
  defp prepare(row, existing, languages, params, now) do
    phone = row["phone"]
    contact = Map.get(existing, phone)

    %{
      phone: phone,
      name: row["name"],
      language_id: language_id(row["language"], contact, languages),
      fields: build_fields(row["contact_fields"], now),
      collections: collections(row["collection"]),
      previous_language_id: contact && contact.language_id,
      previous_fields: (contact && contact.fields) || %{},
      active_profile_id: contact && contact.active_profile_id,
      optin?: optin?(params, contact),
      bsp_status: bsp_status(contact)
    }
  end

  # Postgres rejects an ON CONFLICT DO UPDATE that touches the same row twice, so a csv
  # listing a phone more than once has to be folded into a single row first. Merging the
  # field maps in row order reproduces what the old per-row path did: the later row wins.
  @spec dedupe([map()]) :: [map()]
  defp dedupe(prepared) do
    prepared
    |> Enum.reduce(%{}, fn row, acc ->
      Map.update(acc, row.phone, row, fn seen ->
        %{
          row
          | fields: Map.merge(seen.fields, row.fields),
            collections: Enum.uniq(seen.collections ++ row.collections)
        }
      end)
    end)
    |> Map.values()
  end

  @spec build_fields(map() | nil, DateTime.t()) :: map()
  defp build_fields(nil, _now), do: %{}

  defp build_fields(fields, now) do
    fields
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
    |> Map.new(fn {label, value} ->
      shortcode = Glific.string_snake_case(label) |> String.trim()

      {shortcode,
       %{
         value: value,
         label: shortcode,
         type: @field_type,
         inserted_at: now
       }}
    end)
  end

  @spec collections(String.t() | nil) :: [String.t()]
  defp collections(collection) when collection in [nil, ""], do: []

  defp collections(collection) do
    collection
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec language_id(String.t() | nil, map() | nil, map()) :: non_neg_integer()
  defp language_id(language, contact, languages) when language in [nil, ""] do
    if contact, do: contact.language_id, else: languages.default_id
  end

  defp language_id(language, _contact, languages) do
    term = language |> String.trim() |> String.downcase()

    Map.get(languages.lookup, term) ||
      match_language_prefix(term, languages.ordered) ||
      languages.default_id
  end

  @spec match_language_prefix(String.t(), [{String.t(), non_neg_integer()}]) ::
          non_neg_integer() | nil
  defp match_language_prefix(term, ordered) do
    Enum.find_value(ordered, fn {key, id} ->
      if String.starts_with?(key, term), do: id
    end)
  end

  @spec optin?(map(), map() | nil) :: boolean()
  defp optin?(%{type: "move_contact"}, _contact), do: false

  defp optin?(params, contact), do: optin_allowed?(contact) and may_optin?(params.user)

  @spec optin_allowed?(map() | nil) :: boolean()
  defp optin_allowed?(nil), do: true

  defp optin_allowed?(contact) do
    contact.status != :blocked and is_nil(contact.optin_time) and is_nil(contact.optout_time)
  end

  @spec may_optin?(map()) :: boolean()
  defp may_optin?(user) do
    Authorize.valid_role?(user.roles, :manager) or user.upload_contacts == true
  end

  @spec bsp_status(map() | nil) :: atom()
  defp bsp_status(nil), do: :hsm

  defp bsp_status(%{last_message_at: nil}), do: :hsm

  defp bsp_status(%{last_message_at: last_message_at}) do
    if Timex.compare(last_message_at, Glific.go_back_time(24)) > 0,
      do: :session_and_hsm,
      else: :hsm
  end

  @spec upsert_contacts([map()], map(), DateTime.t()) :: %{String.t() => non_neg_integer()}
  defp upsert_contacts([], _params, _now), do: %{}

  defp upsert_contacts(prepared, params, now) do
    {optin, plain} = Enum.split_with(prepared, & &1.optin?)

    Map.merge(
      do_upsert(plain, params, now, false),
      do_upsert(optin, params, now, true)
    )
  end

  @spec do_upsert([map()], map(), DateTime.t(), boolean()) :: %{String.t() => non_neg_integer()}
  defp do_upsert([], _params, _now, _optin?), do: %{}

  defp do_upsert(rows, params, now, optin?) do
    entries = Enum.map(rows, &contact_entry(&1, params, now, optin?))

    {_count, saved} =
      Repo.insert_all(Contact, entries,
        on_conflict: on_conflict(optin?),
        conflict_target: [:phone, :organization_id],
        returning: [:id, :phone, :fields]
      )

    Map.new(saved, &{&1.phone, %{id: &1.id, fields: &1.fields}})
  end

  @spec contact_entry(map(), map(), DateTime.t(), boolean()) :: map()
  defp contact_entry(row, params, now, false) do
    %{
      phone: row.phone,
      name: row.name,
      language_id: row.language_id,
      fields: row.fields,
      contact_type: "WABA",
      last_communication_at: DateTime.truncate(now, :second),
      organization_id: params.organization_id,
      inserted_at: now,
      updated_at: now
    }
  end

  defp contact_entry(row, params, now, true) do
    row
    |> contact_entry(params, now, false)
    |> Map.merge(%{
      optin_time: DateTime.truncate(now, :second),
      optin_status: true,
      optin_method: "Import",
      optout_time: nil,
      status: :valid,
      bsp_status: row.bsp_status
    })
  end

  @spec on_conflict(boolean()) :: Ecto.Query.t()
  defp on_conflict(false) do
    from(c in Contact,
      update: [
        set: [
          name: fragment("EXCLUDED.name"),
          language_id: fragment("EXCLUDED.language_id"),
          fields: fragment("? || EXCLUDED.fields", c.fields),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
    )
  end

  defp on_conflict(true) do
    from(c in Contact,
      update: [
        set: [
          name: fragment("EXCLUDED.name"),
          language_id: fragment("EXCLUDED.language_id"),
          fields: fragment("? || EXCLUDED.fields", c.fields),
          updated_at: fragment("EXCLUDED.updated_at"),
          optin_time: fragment("EXCLUDED.optin_time"),
          optin_status: fragment("EXCLUDED.optin_status"),
          optin_method: fragment("EXCLUDED.optin_method"),
          optout_time: fragment("EXCLUDED.optout_time"),
          status: fragment("EXCLUDED.status"),
          bsp_status: fragment("EXCLUDED.bsp_status")
        ]
      ]
    )
  end

  @spec sync_profiles([map()], map(), DateTime.t()) :: :ok
  defp sync_profiles(prepared, saved, now) do
    contact_ids =
      prepared
      |> Enum.filter(&(is_integer(&1.active_profile_id) and &1.fields != %{}))
      |> Enum.map(&Map.get(saved, &1.phone))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    if contact_ids != [] do
      from(p in Profiles.Profile,
        join: c in Contact,
        on: c.active_profile_id == p.id,
        where: c.id in ^contact_ids,
        update: [set: [fields: c.fields, updated_at: ^DateTime.truncate(now, :second)]]
      )
      |> Repo.update_all([])
    end

    :ok
  end

  @spec upsert_field_registry([map()], map(), DateTime.t()) :: :ok
  defp upsert_field_registry(prepared, params, now) do
    now = DateTime.truncate(now, :second)

    entries =
      prepared
      |> Enum.flat_map(&Map.keys(&1.fields))
      |> Enum.uniq()
      |> Enum.map(
        &%{
          name: &1,
          shortcode: &1,
          value_type: :text,
          scope: :contact,
          organization_id: params.organization_id,
          inserted_at: now,
          updated_at: now
        }
      )

    Repo.insert_all(ContactsField, entries, on_conflict: :nothing)
    :ok
  end

  @spec insert_histories([map()], map(), map(), DateTime.t()) :: :ok
  defp insert_histories(prepared, saved, params, now) do
    entries = Enum.flat_map(prepared, &history_entries(&1, saved, params, now))

    Repo.insert_all(ContactHistory, entries)
    :ok
  end

  @spec history_entries(map(), map(), map(), DateTime.t()) :: [map()]
  defp history_entries(row, saved, params, now) do
    case Map.get(saved, row.phone) do
      nil ->
        []

      %{id: contact_id} ->
        fields_history(row, contact_id, params, now) ++
          Enum.reject(
            [
              language_history(row, contact_id, params, now),
              optin_history(row, contact_id, params, now)
            ],
            &is_nil/1
          )
    end
  end

  @spec fields_history(map(), non_neg_integer(), map(), DateTime.t()) :: [map()]
  defp fields_history(row, contact_id, params, now) do
    Enum.map(row.fields, fn {shortcode, field} ->
      history(contact_id, params, now, "contact_fields_updated", %{
        event_label: "Value for #{field.label} is updated to #{field.value}",
        event_meta: %{
          field: %{
            data: shortcode,
            label: field.label,
            value: field.value,
            old_value: Map.get(row.previous_fields, shortcode),
            new_value: field.value
          }
        }
      })
    end)
  end

  @spec language_history(map(), non_neg_integer(), map(), DateTime.t()) :: map() | nil
  defp language_history(%{previous_language_id: previous, language_id: current}, _id, _p, _now)
       when is_nil(previous) or previous == current,
       do: nil

  defp language_history(row, contact_id, params, now) do
    labels = params.language_labels
    old_label = Map.get(labels, row.previous_language_id)
    new_label = Map.get(labels, row.language_id)

    history(contact_id, params, now, "contact_language_updated", %{
      event_label: "Changed contact language to #{new_label} from #{old_label}, via import.",
      event_meta: %{
        language: %{
          id: row.language_id,
          label: new_label,
          old_language: row.previous_language_id
        }
      }
    })
  end

  @spec optin_history(map(), non_neg_integer(), map(), DateTime.t()) :: map() | nil
  defp optin_history(%{optin?: false}, _contact_id, _params, _now), do: nil

  defp optin_history(_row, contact_id, params, now) do
    history(contact_id, params, now, "contact_opted_in", %{
      event_label: "contact opted in, via Import",
      event_meta: %{method: "Import", utc_time: now}
    })
  end

  @spec history(non_neg_integer(), map(), DateTime.t(), String.t(), map()) :: map()
  defp history(contact_id, params, now, event_type, attrs) do
    %{
      contact_id: contact_id,
      event_type: event_type,
      event_datetime: DateTime.truncate(now, :second),
      organization_id: params.organization_id,
      inserted_at: now,
      updated_at: now
    }
    |> Map.merge(attrs)
  end

  @spec link_collections([map()], map(), map(), DateTime.t()) :: :ok
  defp link_collections(prepared, saved, params, now) do
    now = DateTime.truncate(now, :second)

    groups =
      prepared
      |> Enum.flat_map(& &1.collections)
      |> Enum.uniq()
      |> ensure_groups(params.organization_id)

    entries =
      for row <- prepared,
          saved_row = Map.get(saved, row.phone),
          not is_nil(saved_row),
          label <- row.collections,
          group_id = Map.get(groups, label),
          not is_nil(group_id) do
        %{
          contact_id: saved_row.id,
          group_id: group_id,
          organization_id: params.organization_id,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(ContactGroup, Enum.uniq(entries), on_conflict: :nothing)
    :ok
  end

  @spec ensure_groups([String.t()], non_neg_integer()) :: %{String.t() => non_neg_integer()}
  defp ensure_groups(labels, organization_id) do
    Map.new(labels, fn label ->
      {:ok, group} = Groups.get_or_create_group_by_label(label, organization_id)
      {label, group.id}
    end)
  end

  @spec delete_contact(map(), map(), map()) :: map()
  defp delete_contact(row, params, errors) do
    phone = row["phone"]

    if Authorize.valid_role?(params.user.roles, :manager) || params.user.upload_contacts do
      case Repo.get_by(Contact, %{phone: phone}) do
        nil ->
          Map.put(errors, phone, "Contact does not exist")

        contact ->
          delete_one(contact, phone, errors)
      end
    else
      Map.put(errors, phone, "This user #{params.user.name} doesn't have enough permission")
    end
  end

  @spec delete_one(Contact.t(), String.t(), map()) :: map()
  defp delete_one(contact, phone, errors) do
    case Contacts.delete_contact(contact) do
      {:ok, _contact} -> errors
      {:error, reason} -> Map.put(errors, phone, to_string(reason))
    end
  catch
    kind, reason ->
      Glific.log_error(
        "Deleting #{phone} during import failed: " <>
          Glific.SafeLog.safe_inspect({kind, reason})
      )

      Map.put(errors, phone, "Could not delete this contact, please retry it on its own")
  end
end
