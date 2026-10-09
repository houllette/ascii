defmodule Ascii.Pieces.DesertNightTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.DesertNight
  use Ascii.GoldenCase, slug: "desert-night", piece: Ascii.Pieces.DesertNight

  alias Ascii.Pieces.DesertNight

  # The frame's shortcuts (the fast powers and the margins that guard them,
  # the glint skipped where it adds nothing, the airglow's shared noise
  # lattice) must draw exactly what the long way draws, at any time, in
  # colour and in one ink.
  property "the shortcuts draw what the exact path draws" do
    state =
      Ascii.TestCache.fetch({:init, DesertNight}, fn ->
        DesertNight.init(DesertNight.meta().options)
      end)

    check all(
            times <- list_of(float(min: 0.0, max: 120.0), min_length: 1, max_length: 3),
            max_runs: 20
          ) do
      for color? <- [true, false] do
        env = %Ascii.Env{cols: 200, rows: 100, color?: color?}

        Enum.reduce(times, {state, %{state | exact?: true}}, fn t, {fast, exact} ->
          {text, colors, fast} = DesertNight.frame(fast, t, env)
          {want_text, want_colors, exact} = DesertNight.frame(exact, t, env)
          at = "at t=#{t}, colour: #{color?}"
          assert IO.iodata_to_binary(text) == IO.iodata_to_binary(want_text), "text differs #{at}"
          assert colors == want_colors, "colours differ #{at}"
          {fast, exact}
        end)
      end
    end
  end
end
