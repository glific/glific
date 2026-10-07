defmodule GlificCredo.Checks.ContactPhoneLookup do
  @moduledoc """
  Custom Credo check that forbids looking a contact up by phone outside `Glific.Contacts`.

  `contacts.phone` can be NULL (a contact who only logs in with a username), and a phone lookup
  with a nil phone is either a crash (`Repo.get_by/2` raises on nil) or, if someone "fixes" that
  with `is_nil(c.phone)`, a lookup that matches every phone-less contact. `Contacts.fetch_by_phone/2`
  is the single function that refuses a nil phone before querying, so every phone lookup must go
  through it.

  The check flags `Repo.get_by/2`, `Repo.get_by!/2` and `Repo.fetch_by/2` (on `Repo` or
  `RepoReplica`, aliased or fully qualified) whose queryable is `Contact` and whose clauses carry a
  `:phone` key. Test files and the modules in `:excluded_modules` (by default `Glific.Contacts`,
  which implements the lookup) are exempt.

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

      raises when `phone` is nil, and the tempting fix (`where: is_nil(c.phone)`) silently
      returns an arbitrary phone-less contact.

      Use `Glific.Contacts.fetch_by_phone/2` instead. It returns `{:error, :no_phone}` for a nil
      or empty phone without querying, `{:error, :not_found}` when no contact matches, and
      `{:ok, contact}` otherwise.
      """,
      params: [
        excluded_modules: "Modules permitted to look a contact up by phone directly."
      ]
    ]

  @repo_modules [:Repo, :RepoReplica]
  @lookup_functions [:get_by, :get_by!, :fetch_by]

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

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp phone_clause?({:%{}, _, pairs}) when is_list(pairs), do: phone_key?(pairs)
  defp phone_clause?(pairs) when is_list(pairs), do: phone_key?(pairs)
  defp phone_clause?(_clauses), do: false

  defp phone_key?(pairs), do: Enum.any?(pairs, &match?({:phone, _}, &1))

  defp issue_for(issue_meta, meta, function) do
    format_issue(
      issue_meta,
      message:
        "Use `Glific.Contacts.fetch_by_phone/2` instead of `Repo.#{function}(Contact, phone: ...)` so a nil phone never reaches the query.",
      trigger: "#{function}",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
