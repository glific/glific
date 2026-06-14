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
    case Caches.get(organization_id, @cache_tag_maps_key) do
      {:ok, false} ->
        fetch_and_cache_tag_maps(organization_id)

      {:ok, tag_maps} ->
        tag_maps

      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve tag maps for #{organization_id}: #{error}"
        )
    end
  end

  # Fetches tag maps from DB in the caller's process (preserving SQL Sandbox ownership)
  # and stores the result in the cache.
  @spec fetch_and_cache_tag_maps(non_neg_integer) :: map()
  defp fetch_and_cache_tag_maps(organization_id) do
    Repo.put_organization_id(organization_id)
    attrs = %{shortcode: "numeric", organization_id: organization_id}

    tag_maps =
      case Repo.fetch_by(Tag, attrs) do
        {:ok, tag} -> %{:numeric_tag_id => tag.id}
        _ -> %{}
      end
      |> Map.put(:keyword_map, Taggers.Keyword.get_keyword_map(attrs))
      |> Map.put(:status_map, Status.get_status_map(attrs))

    Caches.set(organization_id, @cache_tag_maps_key, tag_maps)
    tag_maps
  end

  @doc """
  Reset the cache, typically called when tags are either created or updated
  """

  @spec reset_tag_maps(non_neg_integer) :: list()
  def reset_tag_maps(organization_id),
    do: Caches.remove(organization_id, [@cache_tag_maps_key])
end
