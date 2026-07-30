defmodule Glific.Scripts.NormalizeContactPhones do
  @moduledoc """
  One-off backfill that rewrites existing `contacts.phone` values into the canonical
  E.164-without-`+` form produced by `Glific.Contacts.normalize_phone/1`.

  Canonicalization was introduced on the write and lookup paths only (#5400). Rows written
  before that still hold raw variants — `+919876543210`, `91 98765 43210`, `+91-98765-43210` —
  and a lookup with the canonical form no longer matches them, so those contacts become
  unreachable by phone. This script aligns the stored data with the new invariant.

  ## Classification

  Every contact lands in exactly one bucket:

    * `:canonical` — already stored canonically; untouched.
    * `:simulator` — simulator number (`9876543210…`); never rewritten.
    * `:rename` — normalizes to a value no other contact in the org holds, so a plain
      `UPDATE` is enough.
    * `:duplicate` — normalizes onto a phone another contact in the org already holds. Only
      merged when `merge: true`, otherwise counted and reported.
    * `:unparseable` — `ExPhoneNumber` rejects it, e.g. a bare 10-digit number with no country
      code (`9876543210`). Left alone: inferring a country code would invent data, so these
      are reported for a human to decide on.
    * `:manual` — a duplicate whose losing row is referenced by `users` or `organizations`, or
      whose merge needs a delete outside the join-table allowlist. Skipped and reported.

  ## Run from IEx (`gigalixir remote_console`)

      # 1. read-only report across every org — always start here
      iex> Glific.Scripts.NormalizeContactPhones.audit()
      %{totals: %{examined: 812_004, rename: 1_142, duplicate: 87, ...}, orgs: [...]}

      # 2. same classification for one org, with more example rows
      iex> Glific.Scripts.NormalizeContactPhones.audit(organization_id: 1, samples: 50)

      # 3. rewrite only the unambiguous rows; duplicates are still just reported
      iex> Glific.Scripts.NormalizeContactPhones.run(dry_run: false)

      # 4. opt in to merging duplicates, once the audit output looks right
      iex> Glific.Scripts.NormalizeContactPhones.run(dry_run: false, merge: true)

  `run/1` defaults to `dry_run: true, merge: false`, so an accidental call writes nothing.
  It is idempotent — a second pass reports everything as `:canonical`.

  ## What a merge does

  Per duplicate pair, inside one transaction: re-point every foreign key that references
  `contacts` (discovered from `pg_constraint`, so new tables are picked up automatically)
  from the losing row onto the surviving canonical row, delete the losing row's join-table
  rows that would violate a unique index, carry over opt-in/opt-out and activity fields, then
  delete the losing row. Deleting a colliding row is only allowed in the pure join tables
  `contacts_groups`, `contacts_tags`, `contacts_wa_groups`, `message_broadcast_contacts` and
  `wa_reactions`; a collision anywhere else rolls the pair back and reports it as `:manual`
  rather than destroying real data.

  ## Before running on production

  Renames bump `updated_at`, so the BigQuery update sync will re-export every touched
  contact, and a large batch writes near-identical timestamps — the tied-`updated_at`
  pattern behind the sync memory spike in #5468. Run it after that fix is deployed, or in
  chunks via `organization_id:`.
  """

  import Ecto.Query
  require Logger

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Repo,
    SafeLog
  }

  @batch_size 500
  @mergeable_join_tables ~w(contacts_groups contacts_tags contacts_wa_groups
                            message_broadcast_contacts wa_reactions)
  @blocking_tables ~w(users organizations)

  @typedoc "Per-organization counters and example rows."
  @type report :: %{
          organization_id: non_neg_integer(),
          examined: non_neg_integer(),
          canonical: non_neg_integer(),
          simulator: non_neg_integer(),
          rename: non_neg_integer(),
          duplicate: non_neg_integer(),
          merged: non_neg_integer(),
          unparseable: non_neg_integer(),
          manual: non_neg_integer(),
          samples: map()
        }

  @doc """
  Classify every contact without writing anything.
  """
  @spec audit(keyword()) :: %{totals: map(), orgs: [report()]}
  def audit(opts \\ []), do: run(Keyword.merge(opts, dry_run: true, merge: false))

  @doc """
  Classify every contact and, unless `dry_run: true`, rewrite the non-canonical ones.
  """
  @spec run(keyword()) :: %{totals: map(), orgs: [report()]}
  def run(opts \\ []) do
    opts = Keyword.merge([dry_run: true, merge: false, samples: 10], opts)
    fks = referencing_columns()

    orgs =
      opts
      |> organization_ids()
      |> Enum.map(&process_org(&1, fks, opts))

    %{totals: totals(orgs), orgs: orgs}
  end

  @spec organization_ids(keyword()) :: [non_neg_integer()]
  defp organization_ids(opts) do
    case Keyword.get(opts, :organization_id) do
      nil -> Partners.list_organizations() |> Enum.map(& &1.id)
      org_id -> [org_id]
    end
  end

  @spec process_org(non_neg_integer(), [{String.t(), String.t()}], keyword()) :: report()
  defp process_org(org_id, fks, opts) do
    Repo.put_organization_id(org_id)

    {report, _claimed} =
      org_id
      |> stream_contacts()
      |> Enum.reduce({empty_report(org_id), MapSet.new()}, &handle_contact(&1, &2, fks, opts))

    Logger.info(
      "NormalizeContactPhones org=#{org_id} #{SafeLog.safe_inspect(Map.delete(report, :samples))}"
    )

    report
  end

  @spec stream_contacts(non_neg_integer()) :: Enumerable.t()
  defp stream_contacts(org_id) do
    Stream.resource(
      fn -> 0 end,
      fn last_id ->
        rows =
          Contact
          |> where([c], c.organization_id == ^org_id and c.id > ^last_id)
          |> order_by([c], asc: c.id)
          |> limit(@batch_size)
          |> Repo.all()

        if rows == [], do: {:halt, last_id}, else: {rows, List.last(rows).id}
      end,
      fn _ -> :ok end
    )
  end

  @spec handle_contact(Contact.t(), {report(), MapSet.t()}, [{String.t(), String.t()}], keyword()) ::
          {report(), MapSet.t()}
  defp handle_contact(contact, {report, claimed}, fks, opts) do
    report = Map.update!(report, :examined, &(&1 + 1))
    normalized = Contacts.normalize_phone(contact.phone)

    case classify(contact, normalized, claimed) do
      :rename ->
        unless opts[:dry_run], do: rename(contact, normalized)
        {tally(report, :rename, contact, normalized, opts), MapSet.put(claimed, normalized)}

      :duplicate ->
        {resolve_duplicate(contact, normalized, report, fks, opts), claimed}

      bucket ->
        {tally(report, bucket, contact, normalized, opts), claimed}
    end
  end

  @spec classify(Contact.t(), String.t(), MapSet.t()) ::
          :canonical | :simulator | :rename | :duplicate | :unparseable
  defp classify(%Contact{phone: phone}, normalized, claimed) do
    cond do
      Contacts.simulator_contact?(phone) -> :simulator
      normalized == phone and parseable?(phone) -> :canonical
      normalized == phone -> :unparseable
      taken?(normalized, claimed) -> :duplicate
      true -> :rename
    end
  end

  @spec parseable?(String.t()) :: boolean()
  defp parseable?(phone), do: match?({:ok, _}, Contacts.parse_phone_number(phone))

  # `claimed` covers rows this run has already renamed onto `normalized`, which a dry run
  # would otherwise miss because nothing was written.
  @spec taken?(String.t(), MapSet.t()) :: boolean()
  defp taken?(normalized, claimed) do
    MapSet.member?(claimed, normalized) or
      Repo.exists?(from(c in Contact, where: c.phone == ^normalized))
  end

  @spec rename(Contact.t(), String.t()) :: any()
  defp rename(contact, normalized) do
    Contact
    |> where([c], c.id == ^contact.id)
    |> Repo.update_all(set: [phone: normalized, updated_at: DateTime.utc_now()])
  end

  @spec resolve_duplicate(
          Contact.t(),
          String.t(),
          report(),
          [{String.t(), String.t()}],
          keyword()
        ) :: report()
  defp resolve_duplicate(contact, normalized, report, fks, opts) do
    survivor = Repo.get_by(Contact, phone: normalized)

    cond do
      opts[:dry_run] or not opts[:merge] ->
        tally(report, :duplicate, contact, normalized, opts)

      is_nil(survivor) ->
        tally(report, :manual, contact, normalized, opts, "canonical row not found")

      reason = blocking_reference(contact) ->
        tally(report, :manual, contact, normalized, opts, "referenced by #{reason}")

      true ->
        apply_merge(contact, survivor, normalized, report, fks, opts)
    end
  end

  @spec apply_merge(
          Contact.t(),
          Contact.t(),
          String.t(),
          report(),
          [{String.t(), String.t()}],
          keyword()
        ) :: report()
  defp apply_merge(loser, survivor, normalized, report, fks, opts) do
    case merge(loser, survivor, fks) do
      {:ok, _} ->
        report
        |> tally(:duplicate, loser, normalized, opts)
        |> Map.update!(:merged, &(&1 + 1))

      {:error, reason} ->
        Logger.warning("NormalizeContactPhones: merge of contact #{loser.id} skipped — #{reason}")
        tally(report, :manual, loser, normalized, opts, reason)
    end
  end

  @spec merge(Contact.t(), Contact.t(), [{String.t(), String.t()}]) ::
          {:ok, Contact.t()} | {:error, String.t()}
  defp merge(loser, survivor, fks) do
    Repo.transaction(fn ->
      Enum.each(fks, &repoint(&1, loser.id, survivor.id))

      survivor
      |> Contact.changeset(merge_attrs(survivor, loser))
      |> Repo.update!()

      Repo.delete!(loser)
      survivor
    end)
  end

  @spec repoint({String.t(), String.t()}, non_neg_integer(), non_neg_integer()) :: :ok
  defp repoint({table, column}, loser_id, survivor_id) do
    table
    |> unique_indexes()
    |> Enum.filter(&(column in &1))
    |> Enum.each(&drop_colliding(table, column, &1, loser_id, survivor_id))

    Repo.query!(~s[UPDATE "#{table}" SET "#{column}" = $1 WHERE "#{column}" = $2], [
      survivor_id,
      loser_id
    ])

    :ok
  end

  @spec drop_colliding(
          String.t(),
          String.t(),
          [String.t()],
          non_neg_integer(),
          non_neg_integer()
        ) :: any()
  defp drop_colliding(table, column, index_columns, loser_id, survivor_id) do
    predicate = collision_predicate(table, column, index_columns)
    params = [survivor_id, loser_id]

    cond do
      table in @mergeable_join_tables ->
        Repo.query!(~s[DELETE FROM "#{table}" d WHERE #{predicate}], params)

      collisions(table, predicate, params) > 0 ->
        Repo.rollback("#{table} collides on #{Enum.join(index_columns, ", ")}")

      true ->
        :ok
    end
  end

  @spec collision_predicate(String.t(), String.t(), [String.t()]) :: String.t()
  defp collision_predicate(table, column, index_columns) do
    match =
      index_columns
      |> List.delete(column)
      |> Enum.map_join("", &~s[ AND s."#{&1}" = d."#{&1}"])

    ~s[d."#{column}" = $2 AND EXISTS ] <>
      ~s[(SELECT 1 FROM "#{table}" s WHERE s."#{column}" = $1#{match})]
  end

  @spec collisions(String.t(), String.t(), [non_neg_integer()]) :: non_neg_integer()
  defp collisions(table, predicate, params) do
    %{rows: [[count]]} =
      Repo.query!(~s[SELECT count(*) FROM "#{table}" d WHERE #{predicate}], params)

    count
  end

  # `organizations.contact_id` carries a unique index but no foreign key, so it is checked
  # here rather than discovered alongside the real constraints.
  @spec blocking_reference(Contact.t()) :: String.t() | nil
  defp blocking_reference(%Contact{id: id}) do
    Enum.find(@blocking_tables, fn table ->
      %{rows: [[count]]} =
        Repo.query!(~s[SELECT count(*) FROM "#{table}" WHERE contact_id = $1], [id])

      count > 0
    end)
  end

  @spec referencing_columns() :: [{String.t(), String.t()}]
  defp referencing_columns do
    %{rows: rows} =
      Repo.query!("""
      SELECT cl.relname, att.attname
      FROM pg_constraint con
      JOIN pg_class cl ON cl.oid = con.conrelid
      JOIN LATERAL unnest(con.conkey) AS k(attnum) ON true
      JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.attnum
      WHERE con.contype = 'f' AND con.confrelid = 'contacts'::regclass
      ORDER BY cl.relname, att.attname
      """)

    Enum.map(rows, fn [table, column] -> {table, column} end)
  end

  # Expression indexes surface an attnum of 0 and drop out of the join, so anything that did
  # not resolve to a full set of column names is left out — it cannot be reasoned about here.
  @spec unique_indexes(String.t()) :: [[String.t()]]
  defp unique_indexes(table) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT array_agg(att.attname ORDER BY k.ord), ix.indnkeyatts
        FROM pg_index ix
        JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord) ON true
        JOIN pg_attribute att ON att.attrelid = ix.indrelid AND att.attnum = k.attnum
        WHERE ix.indrelid = to_regclass($1)
          AND ix.indisunique
          AND ix.indpred IS NULL
          AND k.ord <= ix.indnkeyatts
        GROUP BY ix.indexrelid, ix.indnkeyatts
        """,
        [table]
      )

    for [columns, key_count] <- rows, length(columns) == key_count, do: columns
  end

  @spec merge_attrs(Contact.t(), Contact.t()) :: map()
  defp merge_attrs(survivor, loser) do
    %{
      name: survivor.name || loser.name,
      fields: Map.merge(loser.fields || %{}, survivor.fields || %{}),
      settings: Map.merge(loser.settings || %{}, survivor.settings || %{}),
      last_message_number: max(survivor.last_message_number, loser.last_message_number),
      last_communication_at:
        latest(
          timestamp(survivor, :last_communication_at),
          timestamp(loser, :last_communication_at)
        )
    }
    |> Map.merge(activity_attrs(survivor, loser))
    |> Map.merge(optin_attrs(survivor, loser))
    |> Map.merge(optout_attrs(survivor, loser))
  end

  @spec activity_attrs(Contact.t(), Contact.t()) :: map()
  defp activity_attrs(survivor, loser) do
    if after?(timestamp(loser, :last_message_at), timestamp(survivor, :last_message_at)),
      do: %{last_message_at: loser.last_message_at, bsp_status: loser.bsp_status},
      else: %{}
  end

  @spec optin_attrs(Contact.t(), Contact.t()) :: map()
  defp optin_attrs(%Contact{optin_time: nil}, %Contact{optin_time: time} = loser)
       when not is_nil(time) do
    %{
      optin_time: loser.optin_time,
      optin_status: loser.optin_status,
      optin_method: loser.optin_method,
      optin_message_id: loser.optin_message_id
    }
  end

  defp optin_attrs(_survivor, _loser), do: %{}

  # An opt-out only carries over when the survivor has none and the loser opted out after the
  # survivor's own opt-in — otherwise a stale opt-out would silence a contact that re-joined.
  @spec optout_attrs(Contact.t(), Contact.t()) :: map()
  defp optout_attrs(%Contact{optout_time: nil} = survivor, %Contact{optout_time: time} = loser)
       when not is_nil(time) do
    if after?(timestamp(loser, :optout_time), timestamp(survivor, :optin_time)),
      do: %{optout_time: loser.optout_time, optout_method: loser.optout_method, status: :invalid},
      else: %{}
  end

  defp optout_attrs(_survivor, _loser), do: %{}

  # `Contact.t()` types its datetime fields with the Ecto column-type atoms rather than
  # `DateTime.t()`, so reading one straight off the struct makes Dialyzer treat every DateTime
  # call on it as unreachable. Going through a plain map read keeps the runtime type.
  @spec timestamp(map(), atom()) :: DateTime.t() | nil
  defp timestamp(contact, key), do: Map.get(contact, key)

  @spec latest(DateTime.t() | nil, DateTime.t() | nil) :: DateTime.t() | nil
  defp latest(left, right), do: if(after?(right, left), do: right, else: left)

  @spec after?(DateTime.t() | nil, DateTime.t() | nil) :: boolean()
  defp after?(nil, _other), do: false
  defp after?(_value, nil), do: true
  defp after?(value, other), do: DateTime.compare(value, other) == :gt

  @spec empty_report(non_neg_integer()) :: report()
  defp empty_report(org_id) do
    %{
      organization_id: org_id,
      examined: 0,
      canonical: 0,
      simulator: 0,
      rename: 0,
      duplicate: 0,
      merged: 0,
      unparseable: 0,
      manual: 0,
      samples: %{}
    }
  end

  @spec tally(report(), atom(), Contact.t(), String.t(), keyword(), String.t() | nil) :: report()
  defp tally(report, bucket, contact, normalized, opts, reason \\ nil)

  defp tally(report, bucket, _contact, _normalized, _opts, _reason)
       when bucket in [:canonical, :simulator] do
    Map.update!(report, bucket, &(&1 + 1))
  end

  defp tally(report, bucket, contact, normalized, opts, reason) do
    sample =
      %{id: contact.id, phone: contact.phone, normalized: normalized}
      |> maybe_put_reason(reason)

    report
    |> Map.update!(bucket, &(&1 + 1))
    |> Map.update!(:samples, fn samples ->
      Map.update(samples, bucket, [sample], fn existing ->
        if length(existing) < opts[:samples], do: existing ++ [sample], else: existing
      end)
    end)
  end

  @spec maybe_put_reason(map(), String.t() | nil) :: map()
  defp maybe_put_reason(sample, nil), do: sample
  defp maybe_put_reason(sample, reason), do: Map.put(sample, :reason, reason)

  @spec totals([report()]) :: map()
  defp totals(reports) do
    ~w(examined canonical simulator rename duplicate merged unparseable manual)a
    |> Map.new(fn key -> {key, Enum.sum(Enum.map(reports, &Map.fetch!(&1, key)))} end)
  end
end
