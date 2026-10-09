defmodule Ascii.PerfTest do
  # Timing: run alone, not alongside the rest of the suite.
  use ExUnit.Case

  alias Mix.Tasks.Ascii.Perf

  @moduletag :perf
  @moduletag timeout: :infinity

  for {slug, mod} <- Ascii.Registry.all() do
    @tag slug: slug
    test "#{slug} stays within three times upstream's frame budget" do
      r = Perf.measure(unquote(slug), unquote(mod))

      assert r.avg <= 3 * r.budget,
             "#{r.slug}: #{Float.round(r.avg, 2)} ms a frame on average, budget #{r.budget} ms (3x: #{3 * r.budget})"
    end
  end
end
