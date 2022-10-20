defmodule GlificWeb.ReportLiveTest do
  use GlificWeb.ConnCase

  import Phoenix.LiveViewTest
  import Glific.ReportsFixtures

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  defp create_report(_) do
    report = report_fixture()
    %{report: report}
  end

  describe "Index" do
    setup [:create_report]

    test "lists all reports", %{conn: conn, report: report} do
      {:ok, _index_live, html} = live(conn, Routes.report_index_path(conn, :index))

      assert html =~ "Listing Reports"
      assert html =~ report.name
    end

    test "saves new report", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.report_index_path(conn, :index))

      assert index_live |> element("a", "New Report") |> render_click() =~
               "New Report"

      assert_patch(index_live, Routes.report_index_path(conn, :new))

      assert index_live
             |> form("#report-form", report: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#report-form", report: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.report_index_path(conn, :index))

      assert html =~ "Report created successfully"
      assert html =~ "some name"
    end

    test "updates report in listing", %{conn: conn, report: report} do
      {:ok, index_live, _html} = live(conn, Routes.report_index_path(conn, :index))

      assert index_live |> element("#report-#{report.id} a", "Edit") |> render_click() =~
               "Edit Report"

      assert_patch(index_live, Routes.report_index_path(conn, :edit, report))

      assert index_live
             |> form("#report-form", report: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#report-form", report: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.report_index_path(conn, :index))

      assert html =~ "Report updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes report in listing", %{conn: conn, report: report} do
      {:ok, index_live, _html} = live(conn, Routes.report_index_path(conn, :index))

      assert index_live |> element("#report-#{report.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#report-#{report.id}")
    end
  end

  describe "Show" do
    setup [:create_report]

    test "displays report", %{conn: conn, report: report} do
      {:ok, _show_live, html} = live(conn, Routes.report_show_path(conn, :show, report))

      assert html =~ "Show Report"
      assert html =~ report.name
    end

    test "updates report within modal", %{conn: conn, report: report} do
      {:ok, show_live, _html} = live(conn, Routes.report_show_path(conn, :show, report))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Report"

      assert_patch(show_live, Routes.report_show_path(conn, :edit, report))

      assert show_live
             |> form("#report-form", report: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#report-form", report: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.report_show_path(conn, :show, report))

      assert html =~ "Report updated successfully"
      assert html =~ "some updated name"
    end
  end
end
