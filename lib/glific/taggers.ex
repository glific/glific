defmodule Glific.Taggers do
  @moduledoc """
  The API for a generic tagging system on messages that coordinate with different types of taggers.
  The proposed taggers are:
    Numeric
    Keyword
    Emojis
      Positive
      Negative
    Automated
      Compliments
      Good Bye
      Greeting
      Thank You
      Welcome
      Spam
  """

  alias __MODULE__

  alias Glific.{
    Caches,
    Repo,
    Taggers.Status,
    Tags.Tag
  }

  @cache_tag_maps_key :tag_maps

  @doc """
  Cache all the maps needed by the automation engines. Also include ability to reset
  the cache when tags are updated
  """
  @spec get_tag_maps(non_neg_integer) :: map()
  def get_tag_maps(organization_id) do
    case Caches.fetch(organization_id, @cache_tag_maps_key, &load_tags_map/1) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve tag maps for #{organization_id}: #{error}"
        )

      {_, tag_maps} ->
        tag_maps
    end
  end

  @spec load_tags_map(tuple()) :: {:commit, map()}
  defp load_tags_map(cache_key) do
    {organization_id, @cache_tag_maps_key} = cache_key

    attrs = %{shortcode: "numeric", organization_id: organization_id}

    case Repo.fetch_by(Tag, attrs) do
      {:ok, tag} -> %{:numeric_tag_id => tag.id}
      _ -> %{}
    end
    |> Map.put(:keyword_map, Taggers.Keyword.get_keyword_map(attrs))
    |> Map.put(:status_map, Status.get_status_map(attrs))
  end

  @doc """
  Reset the cache, typically called when tags are either created or updated
  """

  @spec reset_tag_maps(non_neg_integer) :: list()
  def reset_tag_maps(organization_id),
    do: Caches.remove(organization_id, [@cache_tag_maps_key])
end
