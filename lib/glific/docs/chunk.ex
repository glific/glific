defmodule Glific.Docs.Chunk do
  @moduledoc """
  One retrievable piece of the documentation: a heading, its prose, and its source URL.

  `heading_path` is the trail of headings above the section, kept separate from
  the body so it can be shown as prose or prefixed onto the text an embedding
  model sees. A body often never repeats what its heading says.
  """

  @enforce_keys [:doc_file, :heading_path, :body, :content_hash]
  defstruct [
    :doc_file,
    :section_path,
    :heading_path,
    :body,
    :source_url,
    :content_hash
  ]

  @type t() :: %__MODULE__{
          doc_file: String.t(),
          section_path: String.t() | nil,
          heading_path: String.t(),
          body: String.t(),
          source_url: String.t() | nil,
          content_hash: String.t()
        }

  @doc "The text an embedding model sees: the heading trail, then the prose."
  @spec embed_text(t()) :: String.t()
  def embed_text(%__MODULE__{heading_path: heading_path, body: body}),
    do: heading_path <> "\n\n" <> body

  @doc "The last heading in the trail."
  @spec title(t()) :: String.t()
  def title(%__MODULE__{heading_path: heading_path}),
    do: heading_path |> String.split(" › ") |> List.last()
end
