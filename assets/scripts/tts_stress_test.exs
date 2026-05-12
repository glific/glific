# TTS / ffmpeg Stress Test
# Paste the entire defmodule block into an IEx session on staging, then call:
#   TtsStressTest.run_all(1)        -- run all scenarios for org_id 1
#   TtsStressTest.run(1, :large)    -- run a single scenario
#
# Available scenarios:
#   :large        - WhatsApp max-length text (~4096 chars)
#   :languages    - Same sentence in Hindi, Tamil, Telugu, Marathi, Bengali
#   :parallel     - 8 concurrent calls (monitors CPU/memory spikes)
#   :medium_burst - 10 sequential medium texts back-to-back
#   :short_burst  - 20 very short texts (overhead + temp file churn)
#   :unicode      - Emoji-heavy and special-character text
#   :temp_cleanup - Verify no .pcm/.mp3 files leak in /tmp after each run

defmodule TtsStressTest do
  alias Glific.ThirdParty.Gemini

  # ── Test data ────────────────────────────────────────────────────────────────

  # WhatsApp hard limit is 4096 chars. This fills it with a realistic paragraph.
  @large_text String.duplicate(
    "Glific is an open source communication platform designed for the social sector. " <>
    "It enables NGOs and nonprofits to reach communities at scale using WhatsApp. " <>
    "The platform supports multilingual messaging, automated flows, and AI-powered features. ",
    17  # ~4080 chars
  )

  @medium_text """
  Glific helps social sector organizations communicate with their beneficiaries.
  It supports Hindi, Tamil, Telugu, and many other Indian languages.
  The platform is built on Elixir and Phoenix for high scalability.
  """

  @short_text "Hello, this is a test message."

  @languages [
    {"hindi",   "नमस्ते, यह एक परीक्षण संदेश है। हम यह सुनिश्चित करना चाहते हैं कि यह सही ढंग से काम कर रहा है।"},
    {"tamil",   "வணக்கம், இது ஒரு சோதனை செய்தி. இது சரியாக செயல்படுகிறதா என்று சரிபார்க்கிறோம்."},
    {"telugu",  "నమస్కారం, ఇది ఒక పరీక్ష సందేశం. ఇది సరిగ్గా పనిచేస్తుందో లేదో తనిఖీ చేస్తున్నాం."},
    {"marathi", "नमस्कार, हा एक चाचणी संदेश आहे. हे योग्यरित्या काम करत आहे का ते आम्ही तपासत आहोत."},
    {"bengali", "নমস্কার, এটি একটি পরীক্ষামূলক বার্তা। এটি সঠিকভাবে কাজ করছে কিনা তা আমরা যাচাই করছি।"},
    {"english", "Hello, this is a test message. We are verifying that text-to-speech conversion works correctly across all supported languages."}
  ]

  @unicode_text "🎉 Congratulations! Your application is approved ✅. Please visit our office 🏢 at 10:00 AM tomorrow. For queries, call us: +91-98765-43210. \"Thank you\" – The Team 🙏"

  # ── Public API ────────────────────────────────────────────────────────────────

  def run_all(org_id) do
    IO.puts("\n#{"=" |> String.duplicate(60)}")
    IO.puts("TTS / ffmpeg Stress Test  org_id=#{org_id}")
    IO.puts("#{"=" |> String.duplicate(60)}\n")

    for scenario <- [:large, :languages, :parallel, :medium_burst, :short_burst, :unicode, :temp_cleanup] do
      run(org_id, scenario)
      IO.puts("")
    end

    IO.puts("All scenarios complete.")
  end

  def run(org_id, :large) do
    label = "Scenario 1 – Large text (#{String.length(@large_text)} chars)"
    run_single(org_id, @large_text, label)
  end

  def run(org_id, :languages) do
    IO.puts("── Scenario 2 – Multiple languages ──")
    for {lang, text} <- @languages do
      run_single(org_id, text, "  [#{lang}] #{String.length(text)} chars")
    end
  end

  def run(org_id, :parallel) do
    concurrency = 8
    IO.puts("── Scenario 3 – #{concurrency} parallel calls ──")
    mem_before = memory_mb()
    procs_before = ffmpeg_process_count()

    {micros, results} = :timer.tc(fn ->
      1..concurrency
      |> Task.async_stream(
        fn i ->
          text = "Parallel call #{i}. #{@medium_text}"
          {i, timed_call(org_id, text)}
        end,
        max_concurrency: concurrency,
        timeout: 120_000
      )
      |> Enum.to_list()
    end)

    mem_after = memory_mb()
    IO.puts("  Total wall time : #{format_ms(micros)}")
    IO.puts("  Memory delta    : #{Float.round(mem_after - mem_before, 1)} MB")
    IO.puts("  Max ffmpeg procs observed: #{procs_before} → check AppSignal for peak")
    print_parallel_results(results)
  end

  def run(org_id, :medium_burst) do
    count = 10
    IO.puts("── Scenario 4 – #{count} sequential medium texts ──")
    results =
      for i <- 1..count do
        timed_call(org_id, "Message #{i}. #{@medium_text}")
      end
    print_summary("medium_burst", results)
  end

  def run(org_id, :short_burst) do
    count = 20
    IO.puts("── Scenario 5 – #{count} sequential short texts ──")
    results =
      for i <- 1..count do
        timed_call(org_id, "#{@short_text} (#{i})")
      end
    print_summary("short_burst", results)
  end

  def run(org_id, :unicode) do
    IO.puts("── Scenario 6 – Unicode / emoji / special characters ──")
    run_single(org_id, @unicode_text, "  [unicode] #{String.length(@unicode_text)} chars")
  end

  def run(org_id, :temp_cleanup) do
    IO.puts("── Scenario 7 – Temp file cleanup verification ──")
    tmp = System.tmp_dir!()
    before_count = count_tmp_audio_files(tmp)

    # Run 5 conversions and count files before/after each
    for i <- 1..5 do
      {_result, _ms} = timed_call(org_id, "Cleanup test #{i}. #{@short_text}")
      after_count = count_tmp_audio_files(tmp)
      leaked = after_count - before_count
      status = if leaked == 0, do: "✓ clean", else: "✗ #{leaked} file(s) leaked"
      IO.puts("  Run #{i}: #{status}")
    end

    final_count = count_tmp_audio_files(tmp)
    IO.puts("  Net temp files: #{final_count - before_count} (should be 0)")
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp run_single(org_id, text, label) do
    IO.puts("── #{label} ──")
    {result, ms} = timed_call(org_id, text)
    status = if match?(%{success: true}, result), do: "✓", else: "✗"
    IO.puts("  #{status} #{ms} ms  →  #{inspect_result(result)}")
  end

  defp timed_call(org_id, text) do
    {micros, result} = :timer.tc(fn -> Gemini.text_to_speech(org_id, text) end)
    {result, div(micros, 1000)}
  end

  defp print_summary(label, results) do
    times   = Enum.map(results, fn {_, ms} -> ms end)
    success = Enum.count(results, fn {r, _} -> match?(%{success: true}, r) end)
    IO.puts("  #{label}: #{success}/#{length(results)} succeeded")
    IO.puts("  min=#{Enum.min(times)}ms  max=#{Enum.max(times)}ms  avg=#{avg(times)}ms")
  end

  defp print_parallel_results(results) do
    Enum.each(results, fn
      {:ok, {i, {%{success: true}, ms}}}  -> IO.puts("  [#{i}] ✓ #{ms} ms")
      {:ok, {i, {result, ms}}}            -> IO.puts("  [#{i}] ✗ #{ms} ms  #{inspect_result(result)}")
      {:exit, reason}                     -> IO.puts("  [?] crashed: #{inspect(reason)}")
    end)
  end

  defp inspect_result(%{success: true, media_url: url}), do: "media_url=#{url}"
  defp inspect_result(%{success: false} = r),            do: "FAILED: #{inspect(r)}"
  defp inspect_result(other),                            do: inspect(other)

  defp memory_mb do
    :erlang.memory(:total) / (1024 * 1024)
  end

  defp ffmpeg_process_count do
    case System.cmd("sh", ["-c", "ps aux | grep '[f]fmpeg' | wc -l"]) do
      {count, 0} -> String.trim(count) |> String.to_integer()
      _          -> -1
    end
  end

  defp count_tmp_audio_files(tmp) do
    File.ls!(tmp)
    |> Enum.count(fn f -> String.ends_with?(f, ".pcm") or String.ends_with?(f, ".mp3") end)
  end

  defp avg([]),   do: 0
  defp avg(list), do: div(Enum.sum(list), length(list))

  defp format_ms(micros), do: "#{div(micros, 1000)} ms"
end
