defmodule Glific.Scripts.TtsStressTestTest do
  use Glific.DataCase

  import ExUnit.CaptureIO

  alias Glific.Scripts.TtsStressTest

  test "run/2 :temp_cleanup reports no leaked temp files when TTS fails", %{
    organization_id: organization_id
  } do
    Tesla.Mock.mock(fn %{method: :post} -> %Tesla.Env{status: 500, body: %{}} end)

    output = capture_io(fn -> TtsStressTest.run(organization_id, :temp_cleanup) end)

    assert output =~ "Run 5: ✓ clean"
    assert output =~ "Net temp files: 0"
  end
end
