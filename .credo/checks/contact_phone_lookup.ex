defmodule GlificCredo.Checks.ContactPhoneLookup do
  @moduledoc """
  Custom Credo check that forbids looking a contact up by phone outside `Glific.Contacts`.

  `contacts.phone` can be NULL (a contact who only logs in with a username), and a phone lookup
  with a nil phone is either a crash (`Repo.get_by/2` raises on nil) or, if someone "fixes" that
  with `is_nil(c.phone)`, a lookup that matches every phone-less contact.
  `Contacts.fetch_by_identity/3` is the single function that refuses a nil identifier before
  querying, so every phone lookup must go through it.

  The check flags:

    * `Repo.get_by/2`, `Repo.get_by!/2` and `Repo.fetch_by/2` (on `Repo` or `RepoReplica`, aliased
      or fully qualified) whose queryable is `Contact` and whose clauses carry a `:phone` key;
    * `from(c in Contact, where: ...)` whose `where`/`or_where` compares `c.phone` with `==` or is a
      keyword list with a `:phone` key;
    * `where/3` and `or_where/3` on a `Contact` queryable, called directly or at any stage of a
      pipeline that starts at `Contact`, whose condition compares the first binding's `phone`.

  `is_nil(c.phone)` is not flagged: selecting phone-less contacts is a legitimate query. Test files
  and the modules in `:excluded_modules` (by default `Glific.Contacts`, which implements the lookup)
  are exempt.

  See the [Credo guide on adding checks](https://credo.hexdocs.pm/adding_checks.html).
  """

  use Credo.Check,
    id: "GL1002",
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_modules: ["Glific.Contacts"]],
    explanations: [
      check: """
      A contact lookup keyed on phone, such as

          Repo.get_by(Contact, %{phone: phone})
          from(c in Contact, where: c.phone == ^phone)
          Contact |> where([c], c.phone == ^phone)

      raises when `phone` is nil, and the tempting fix (`where: is_nil(c.phone)`) silently
      returns an arbitrary phone-less contact.

      Use `Glific.Contacts.fetch_by_identity(organization_id, :whatsapp, phone)` instead. It
      returns `{:error, :no_identifier}` for a nil or empty phone without querying,
      `{:error, :not_found}` when no contact matches, and `{:ok, contact}` otherwise.
      """,
      params: [
        excluded_modules: "Modules permitted to look a contact up by phone directly."
      ]
    ]

  @repo_modules [:Repo, :RepoReplica]
  @lookup_functions [:get_by, :get_by!, :fetch_by]
  @where_functions [:where, :or_where]

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(%SourceFile{} = source_file, params) do
    excluded_modules = Params.get(params, :excluded_modules, __MODULE__)

    if test_file?(source_file) or excluded_file?(source_file, excluded_modules) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp test_file?(%SourceFile{filename: filename}) do
    filename =~ ~r{(^|/)test/}
  end

  defp excluded_file?(source_file, excluded_modules) do
    source_file
    |> Credo.Code.prewalk(&collect_module_names/2, [])
    |> Enum.any?(&(&1 in excluded_modules))
  end

  defp collect_module_names({:defmodule, _, [{:__aliases__, _, parts}, _]} = ast, names)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      {ast, [Enum.map_join(parts, ".", &Atom.to_string/1) | names]}
    else
      {ast, names}
    end
  end

  defp collect_module_names(ast, names), do: {ast, names}

  defp traverse(
         {{:., _, [{:__aliases__, meta, repo_parts}, function]}, _,
          [{:__aliases__, _, queryable_parts}, clauses]} = ast,
         issues,
         issue_meta
       )
       when function in @lookup_functions and is_list(repo_parts) and is_list(queryable_parts) do
    if List.last(repo_parts) in @repo_modules and List.last(queryable_parts) == :Contact and
         phone_clause?(clauses) do
      {ast, [issue_for(issue_meta, meta, function) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(
         {:from, meta, [{:in, _, [{binding, _, context}, queryable]}, opts]} = ast,
         issues,
         issue_meta
       )
       when is_atom(binding) and is_atom(context) and is_list(opts) do
    phone_lookup? =
      contact?(queryable) and
        Enum.any?(opts, fn
          {function, condition} when function in @where_functions ->
            phone_condition?(condition, binding)

          _option ->
            false
        end)

    {ast, add_issue_if(issues, phone_lookup?, issue_meta, meta, :from)}
  end

  defp traverse(
         {:|>, _, [queryable, {function, meta, [bindings, condition]}]} = ast,
         issues,
         issue_meta
       )
       when function in @where_functions do
    phone_lookup? =
      contact?(pipeline_head(queryable)) and binding_phone_condition?(bindings, condition)

    {ast, add_issue_if(issues, phone_lookup?, issue_meta, meta, function)}
  end

  defp traverse({function, meta, [queryable, bindings, condition]} = ast, issues, issue_meta)
       when function in @where_functions do
    phone_lookup? = contact?(queryable) and binding_phone_condition?(bindings, condition)
    {ast, add_issue_if(issues, phone_lookup?, issue_meta, meta, function)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp add_issue_if(issues, true, issue_meta, meta, function),
    do: [issue_for(issue_meta, meta, function) | issues]

  defp add_issue_if(issues, false, _issue_meta, _meta, _function), do: issues

  defp pipeline_head({:|>, _, [left, _right]}), do: pipeline_head(left)
  defp pipeline_head(queryable), do: queryable

  defp contact?({:__aliases__, _, parts}) when is_list(parts), do: List.last(parts) == :Contact
  defp contact?(_queryable), do: false

  defp binding_phone_condition?([{binding, _, context} | _], condition)
       when is_atom(binding) and is_atom(context),
       do: phone_condition?(condition, binding)

  defp binding_phone_condition?(_bindings, _condition), do: false

  defp phone_condition?(condition, binding) when is_list(condition) do
    phone_key?(condition) or Enum.any?(condition, &phone_condition?(&1, binding))
  end

  defp phone_condition?(condition, binding) do
    {_ast, found?} =
      Macro.prewalk(condition, false, fn
        {:==, _, [left, right]} = node, found? ->
          {node, found? or phone_field?(left, binding) or phone_field?(right, binding)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp phone_field?({{:., _, [{binding, _, context}, :phone]}, _, []}, binding)
       when is_atom(context),
       do: true

  defp phone_field?(_ast, _binding), do: false

  defp phone_clause?({:%{}, _, pairs}) when is_list(pairs), do: phone_key?(pairs)
  defp phone_clause?(pairs) when is_list(pairs), do: phone_key?(pairs)
  defp phone_clause?(_clauses), do: false

  defp phone_key?(pairs), do: Enum.any?(pairs, &match?({:phone, _}, &1))

  defp issue_for(issue_meta, meta, function) do
    format_issue(
      issue_meta,
      message:
        "Use `Glific.Contacts.fetch_by_identity/3` instead of looking a contact up by phone with `#{function}` so a nil phone never reaches the query.",
      trigger: "#{function}",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
