defmodule Glific.ReportsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Reports` context.
  """

  @doc """
  Generate a report.
  """
  def report_fixture(attrs \\ %{}) do
    {:ok, report} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Glific.Reports.create_report()

    report
  end
end
