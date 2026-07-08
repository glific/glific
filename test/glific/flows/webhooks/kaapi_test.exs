defmodule Glific.Flows.Webhooks.KaapiTest do
  @moduledoc """
  Tests for the shared Kaapi webhook helpers. async: false because the STT/TTS rate-limit
  ExRated buckets are process-global.
  """
  use Glific.DataCase, async: false

  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.Partners

  @max 10
  @window_ms 60_000

  defp bucket_key(organization_id),
    do: "kaapi_stt_tts:#{Partners.organization(organization_id).shortcode}"

  describe "check_rate_limit/1" do
    test "returns :ok while under the per-org budget", %{organization_id: organization_id} do
      key = bucket_key(organization_id)
      ExRated.delete_bucket(key)
      on_exit(fn -> ExRated.delete_bucket(key) end)

      assert :ok == KaapiSupport.check_rate_limit(organization_id)
    end

    test "returns {:snooze, seconds} once the shared STT/TTS budget is exhausted", %{
      organization_id: organization_id
    } do
      key = bucket_key(organization_id)
      ExRated.delete_bucket(key)
      on_exit(fn -> ExRated.delete_bucket(key) end)

      # Consume the whole shared STT/TTS budget for the window.
      for _ <- 1..@max, do: {:ok, _} = ExRated.check_rate(key, @window_ms, @max)

      assert {:snooze, seconds} = KaapiSupport.check_rate_limit(organization_id)
      assert is_integer(seconds) and seconds > 0
    end
  end
end
