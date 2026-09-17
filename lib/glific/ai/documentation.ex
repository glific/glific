defmodule Glific.AI.Documentation do
  @moduledoc """
  Glific's own documentation, split into sections and ranked against a question.

  The documents ship in `priv/glific_ai` and are split on their markdown
  headings, which the authors already sized like answers — a few hundred words
  each. A section is ranked by how many of the question's words it uses, and
  much more heavily by how many appear in its heading, since a heading states
  what its section answers.

  Sections carry the `📖 Source:` URL from the document they came from, which is
  what lets an answer cite where it came from. A section without one inherits
  the nearest URL above it, because the documents give a source per page rather
  than per subsection.

  The ranking assumes a short query of Glific's own terms, which is what
  `Glific.AI.Tools.Documentation` asks the model for. A pasted support message
  ranks far worse, so the words that carry no topic — `the`, `is`, `please`,
  `thanks` — are dropped before scoring: left in, they match almost every
  section and hand the result to whichever section is merely longest.
  """

  require Logger

  @index_key {__MODULE__, :index}

  # A heading match is worth several body matches. It is also what finds the
  # notation the documents only ever write as a placeholder: someone asking
  # about `@results.input` reaches the section headed ".input vs .category",
  # where no whole word matches.
  @heading_weight 4

  # Words that say nothing about the topic. A pasted support message is mostly
  # these, and every one of them matches most of the corpus.
  @stopwords MapSet.new(~w(
    the a an and or but if is are was were be been being of in on at to for
    with from by as it its this that these those i we you they he she them us
    my our your their can could will would should do does did have has had
    not no yes so then than there here what which who whom when where why how
    me am any all some more most other into about also very just only own same
    don now get got please hi hello thanks thank team need help issue problem
    having getting trying tried like want able
  ))

  # Below this a match is coincidence rather than an answer: measured against
  # real support questions, an answerable one scores 7 and up and an off-topic
  # one scores 1.
  @minimum_score 3

  @typedoc """
  One section of a document, as a search result.
  """
  @type section :: %{
          document: String.t(),
          title: String.t(),
          path: String.t(),
          body: String.t(),
          url: String.t() | nil
        }

  @doc """
  The sections that best answer a question, most relevant first.

  A question with no word that carries a topic — "thanks", "can you explain
  that more?" — returns nothing rather than a section that happens to share a
  preposition with it.
  """
  @spec search(String.t(), pos_integer()) :: [section()]
  def search(query, limit \\ 5) do
    case terms(query) do
      [] ->
        []

      terms ->
        index()
        |> Enum.map(&{score(&1, terms), &1})
        |> Enum.filter(fn {score, _section} -> score >= @minimum_score end)
        |> Enum.sort_by(fn {score, _section} -> -score end)
        |> Enum.take(limit)
        |> Enum.map(fn {_score, section} ->
          Map.take(section, [:document, :title, :path, :body, :url])
        end)
    end
  end

  @doc """
  How many sections are indexed, which is what a health check reports.
  """
  @spec count() :: non_neg_integer()
  def count, do: index() |> length()

  @doc """
  Builds the index now, so the first question does not pay for it.

  Called on boot. `:persistent_term.put/2` makes every process scan for the
  value it replaces, which is not something to do inside a request.
  """
  @spec warm() :: :ok
  def warm do
    _index = index()
    :ok
  end

  @spec score(map(), [String.t()]) :: number()
  defp score(section, terms) do
    body = Enum.count(terms, &MapSet.member?(section.terms, &1))
    heading = Enum.count(terms, &heading_match?(section, &1))

    body + @heading_weight * heading
  end

  # A plain word has to be a word of the heading: `ignore` must not reach
  # `ignore_keywords`. Notation is matched as a substring instead, in both
  # directions — the documents write `.input`, and the question writes
  # `@results.input`, so neither contains the other whole.
  @spec heading_match?(map(), String.t()) :: boolean()
  defp heading_match?(section, term) do
    cond do
      String.length(term) <= 3 ->
        false

      notation?(term) ->
        String.contains?(section.heading, term) or
          Enum.any?(String.split(term, "."), fn part ->
            String.length(part) > 3 and String.contains?(section.heading, part)
          end)

      true ->
        Enum.any?(inflections(term), &MapSet.member?(section.heading_terms, &1))
    end
  end

  # The headings name a thing and a question names several of them, or the other
  # way round: "HSM template error" has to reach "Common HSM Template Errors".
  @spec inflections(String.t()) :: [String.t()]
  defp inflections(term) do
    [term, term <> "s", String.trim_trailing(term, "s")]
  end

  @spec notation?(String.t()) :: boolean()
  defp notation?(term), do: String.contains?(term, ".") or String.contains?(term, "@")

  # `.` and `@` are kept inside a word so `@contact.fields.name` survives whole,
  # but a trailing `.` is punctuation: without this, the last word of a sentence
  # indexes as `flow.` and never matches `flow`, and every list marker in the
  # documents indexes as `1.`, `2.`, `3.`.
  @spec terms(String.t()) :: [String.t()]
  defp terms(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9_@.]+/u, trim: true)
    |> Enum.map(&String.trim_trailing(&1, "."))
    |> Enum.reject(&(String.length(&1) < 2 or MapSet.member?(@stopwords, &1)))
    |> Enum.uniq()
  end

  # Built once and kept in `:persistent_term`: the documents do not change while
  # the node is running, and reads of a persistent term copy nothing.
  @spec index() :: [map()]
  defp index do
    case :persistent_term.get(@index_key, nil) do
      nil ->
        built = build()
        :persistent_term.put(@index_key, built)
        built

      built ->
        built
    end
  end

  @spec build() :: [map()]
  defp build do
    sections =
      directory()
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(&sections/1)

    if sections == [] do
      Logger.warning("Glific AI documentation is empty: nothing found in #{directory()}")
    end

    sections
  end

  @spec sections(String.t()) :: [map()]
  defp sections(path) do
    document = Path.basename(path, ".md")

    path
    |> File.read!()
    |> headings()
    |> with_ancestors()
    |> Enum.map(&section(&1, document))
    |> Enum.reject(&(MapSet.size(&1.terms) < 5))
  end

  # Each heading with the lines under it, in document order.
  @spec headings(String.t()) :: [{pos_integer(), String.t(), String.t()}]
  defp headings(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], &collect/2)
    |> Enum.reverse()
    |> Enum.map(fn {level, title, lines} ->
      {level, title, lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()}
    end)
  end

  @spec collect(String.t(), list()) :: list()
  defp collect(line, acc) do
    case Regex.run(~r/^(\#+)\s+(\S.*)$/, line) do
      [_line, hashes, title] ->
        [{String.length(hashes), String.trim(title), []} | acc]

      nil ->
        case acc do
          [{level, title, lines} | rest] -> [{level, title, [line | lines]} | rest]
          [] -> acc
        end
    end
  end

  # A heading alone is often meaningless — "What & why", "Overall layout" — and
  # only means something under the one above it. The chain is carried down so a
  # result can say where it came from. It is deliberately not searched: every
  # section in a chapter would then share the chapter's words, and the chapter
  # would outrank the one section that answers the question.
  #
  # The source URL comes down the same chain. The documents give one per page,
  # on the page's own heading, so a subsection has none of its own and would
  # otherwise be uncitable.
  @spec with_ancestors([{pos_integer(), String.t(), String.t()}]) ::
          [{[String.t()], String.t(), String.t() | nil}]
  defp with_ancestors(headings) do
    headings
    |> Enum.map_reduce([], fn {level, title, body}, open ->
      open = Enum.drop_while(open, fn {above, _title, _url} -> above >= level end)
      path = open |> Enum.reverse() |> Enum.map(&elem(&1, 1)) |> Enum.concat([title])
      url = url(body) || Enum.find_value(open, fn {_level, _title, url} -> url end)

      {{path, body, url}, [{level, title, url} | open]}
    end)
    |> elem(0)
  end

  @spec section({[String.t()], String.t(), String.t() | nil}, String.t()) :: map()
  defp section({path, body, url}, document) do
    title = List.last(path)
    trail = Enum.join(path, " › ")
    heading = String.downcase(title)

    %{
      document: document,
      title: title,
      path: trail,
      heading: heading,
      heading_terms: MapSet.new(terms(title)),
      body: body,
      url: url,
      terms: MapSet.new(terms(title <> " " <> body))
    }
  end

  @spec url(String.t()) :: String.t() | nil
  defp url(body) do
    case Regex.run(~r/Source:\s*(https?:\/\/\S+)/u, body) do
      [_match, url] -> String.trim_trailing(url, ".")
      nil -> nil
    end
  end

  @spec directory() :: String.t()
  defp directory, do: :glific |> :code.priv_dir() |> Path.join("glific_ai")
end
