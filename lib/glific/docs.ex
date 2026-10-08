defmodule Glific.Docs do
  @moduledoc """
  Answers questions about Glific from its own documentation.

  The corpus ships in `priv/docs_kb` and `mix glific.docs.index` embeds it into
  a build artifact. Nothing here is organisation-scoped — the documentation is
  the same for everyone — so none of it touches the database.

      {:ok, text, sources} = Glific.Docs.ask("How do I read a parent flow variable?")

  The assistant reaches the same corpus through
  `Glific.AI.Tools.Documentation`. Not wired into GraphQL or flows.
  """

  alias Glific.Docs.{Answerer, Chunk, Index}

  @doc "Answers a question, returning the text and the sections it came from."
  @spec ask(String.t(), keyword()) :: {:ok, String.t(), [Chunk.t()]} | {:error, term()}
  defdelegate ask(question, opts \\ []), to: Answerer, as: :answer_text

  @doc "Answers a question, returning a lazy token stream and its sources."
  @spec ask_stream(String.t(), keyword()) :: {:ok, Answerer.answer()} | {:error, term()}
  defdelegate ask_stream(question, opts \\ []), to: Answerer, as: :answer

  @doc "How many documentation chunks are indexed."
  @spec count() :: non_neg_integer()
  defdelegate count(), to: Index
end
