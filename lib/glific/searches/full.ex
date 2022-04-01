defmodule Glific.Search.Full do
  @moduledoc """
  Glific interface to Postgres's full text search
  """

  import Ecto.Query

  alias Glific.{
    Flows.FlowLabel,
    Groups.ContactGroup,
    Repo
  }

  @doc """
  Simple wrapper function which calls a helper function after normalizing
  and sanitizing the input. The two functions combined serve to augment
  the query with the link to the fulltext index
  """
  @spec run(Ecto.Query.t(), String.t(), map()) :: Ecto.Query.t()
  def run(query, term, args) do
    query
    |> run_helper(
      term |> normalize(),
      args
    )
  end

  @spec run_include_groups(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp run_include_groups(query, group_ids) when is_list(group_ids) and group_ids != [] do
    group_ids =
      Enum.map(group_ids, fn group_id ->
        {:ok, group_id} = Glific.parse_maybe_integer(group_id)
        group_id
      end)

    query
    |> join(:inner, [m: m], cg in ContactGroup, as: :cg, on: cg.contact_id == m.contact_id)
    |> where([cg: cg], cg.group_id in ^group_ids)
  end

  defp run_include_groups(query, _args), do: query

  @spec run_include_labels(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp run_include_labels(query, label_ids) when is_list(label_ids) and label_ids != [] do
    flow_labels =
      FlowLabel
      |> where([f], f.id in ^label_ids)
      |> select([f], f.name)
      |> Repo.all()

    flow_labels
    |> Enum.reduce(query, fn flow_label, query ->
      where(query, [m: m], ilike(m.flow_label, ^"%#{flow_label}%"))
    end)
  end

  defp run_include_labels(query, _args), do: query

  @spec run_helper(Ecto.Queryable.t(), String.t(), map()) :: Ecto.Queryable.t()
  defp run_helper(query, term, args) when term != nil and term != "" do
    query
    |> where([m: m], ilike(m.body, ^"%#{term}%"))
    |> or_where([c: c], ilike(c.name, ^"%#{term}%") or ilike(c.phone, ^"%#{term}%"))
    |> apply_filters(args.filter)
  end

  defp run_helper(query, _, args),
    do:
      query
      |> apply_filters(args.filter)

  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp apply_filters(query, filter) when is_nil(filter), do: query

  defp apply_filters(query, filter) do
    Enum.reduce(filter, query, fn
      {:include_groups, group_ids}, query ->
        query |> run_include_groups(group_ids)

      {:include_labels, label_ids}, query ->
        query |> run_include_labels(label_ids)

      {:date_range, dates}, query ->
        query |> run_date_range(dates[:from], dates[:to])

      {_key, _value}, query ->
        query
    end)
  end

  @spec normalize(String.t()) :: String.t()
  defp normalize(term) when term != "" and term != nil do
    term
    |> String.downcase()
    |> String.replace(~r/[\n|\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize(term), do: term

  # Filter based on the date range
  @spec run_date_range(Ecto.Queryable.t(), DateTime.t(), DateTime.t()) :: Ecto.Queryable.t()
  defp run_date_range(query, nil, nil), do: query

  defp run_date_range(query, nil, to) do
    query
    |> where([c: c], c.last_message_at <= ^(Timex.to_datetime(to) |> Timex.end_of_day()))
  end

  defp run_date_range(query, from, nil) do
    query
    |> where([c: c], c.last_message_at >= ^Timex.to_datetime(from))
  end

  defp run_date_range(query, from, to) do
    query
    |> where(
      [c: c],
      c.last_message_at >= ^Timex.to_datetime(from) and
        c.last_message_at <= ^(Timex.to_datetime(to) |> Timex.end_of_day())
    )
  end
end
