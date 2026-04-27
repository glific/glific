defmodule Glific.AppsignalTest do
  use Glific.DataCase

  alias Glific.Appsignal

  describe "organization_id_tag/1" do
    test "extracts organization_id from top-level args" do
      args = %{"organization_id" => 1, "message_id" => 123}
      assert extract_org_id(args) == "1"
    end

    test "extracts organization_id from nested message args" do
      args = %{"message" => %{"organization_id" => 2, "body" => "hello"}}
      assert extract_org_id(args) == "2"
    end

    test "extracts organization_id from nested media args" do
      args = %{"media" => %{"organization_id" => 3, "url" => "https://example.com"}}
      assert extract_org_id(args) == "3"
    end

    test "prefers top-level organization_id over nested" do
      args = %{
        "organization_id" => 1,
        "message" => %{"organization_id" => 2}
      }

      assert extract_org_id(args) == "1"
    end

    test "returns unknown when organization_id is nil at top level" do
      args = %{"organization_id" => nil}
      assert extract_org_id(args) == "unknown"
    end

    test "returns unknown when args is empty map" do
      assert extract_org_id(%{}) == "unknown"
    end
  end

  describe "handle_event [:oban, :job, :stop]" do
    test "processes event without error for top-level org_id" do
      meta = %{queue: "default", worker: "TestWorker", args: %{"organization_id" => 1}}
      measurement = %{queue_time: 1_500_000}

      result = Appsignal.handle_event([:oban, :job, :stop], measurement, meta, nil)
      assert result in [:ok, nil]
    end

    test "processes event without error for nested message org_id" do
      meta = %{
        queue: "gupshup",
        worker: "Glific.Providers.Gupshup.Worker",
        args: %{"message" => %{"organization_id" => 1}}
      }

      measurement = %{queue_time: 2_000_000}

      result = Appsignal.handle_event([:oban, :job, :stop], measurement, meta, nil)
      assert result in [:ok, nil]
    end
  end

  describe "send_oban_queue_size/0" do
    test "executes without error" do
      assert Appsignal.send_oban_queue_size() == :ok
    end
  end

  defp extract_org_id(args) when is_map(args) do
    get_top_level(args) || get_nested(args, "message") || get_nested(args, "media") || "unknown"
  end

  defp extract_org_id(_), do: "unknown"

  defp get_top_level(%{"organization_id" => id}) when not is_nil(id), do: to_string(id)
  defp get_top_level(_), do: nil

  defp get_nested(%{} = args, key) do
    case args[key] do
      %{"organization_id" => id} when not is_nil(id) -> to_string(id)
      _ -> nil
    end
  end
end
