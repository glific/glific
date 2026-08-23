defmodule Glific.AI.KnowledgeBase do
  @moduledoc """
  The shared Glific product knowledge base, inlined into `Glific.AI.Skills.AskGlific`'s system
  prompt.

  The content lives in `priv/ai/knowledge_base.md` and is read once, at compile time, into a
  module attribute — not read from disk or cached in Cachex at runtime. This keeps `content/0`
  trivially deterministic (a fixed binary, no I/O, no cache-miss race) and free, which matters
  because `Glific.AI.Skill.system_prompt/1` is called on every step of every run and must be
  byte-identical for provider prompt caching to work. `@external_resource` tells the compiler
  this module depends on the markdown file, so editing the file and recompiling is required for
  the change to take effect — an edit to the markdown alone does not update a running release
  until the app is rebuilt and redeployed. That trade is accepted for this prototype.
  """

  @external_resource "priv/ai/knowledge_base.md"
  @content :glific
           |> :code.priv_dir()
           |> Path.join("ai/knowledge_base.md")
           |> File.read!()

  @doc "The full knowledge base markdown, verbatim."
  @spec content() :: String.t()
  def content, do: @content

  @doc "Byte size of the knowledge base content, so callers/tests can assert on its growth."
  @spec byte_size() :: non_neg_integer()
  def byte_size, do: Kernel.byte_size(@content)
end
