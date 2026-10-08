defmodule AsciiArt.Pieces.FernTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Fern
  use AsciiArt.GoldenCase, slug: "fern", piece: AsciiArt.Pieces.Fern

  alias AsciiArt.Pieces.Fern

  # The frame places points approximately and works again exactly where that
  # could matter; it must always draw what the exact frame draws. Among these
  # times, 22.5, 32.75 and 44.75 each have a cell summed again exactly.
  test "the fast frame is the exact frame" do
    state = Fern.init(Fern.meta().options)
    env = %AsciiArt.Env{cols: 44, rows: 30}

    for t <- [0.0, 0.35, 1.0, 1.7, 2.9, 3.3, 4.45, 7.2, 22.5, 32.75, 44.75, 59.9, 117.3, 3.0e8] do
      {fast, _, _} = Fern.frame(state, t, env)
      exact = Fern.exact_frame(state, t)
      assert IO.iodata_to_binary(fast) == IO.iodata_to_binary(exact), "differs at t=#{t}"
    end
  end

  property "the fast frame is the exact frame at any time" do
    state = Fern.init(Fern.meta().options)
    env = %AsciiArt.Env{cols: 44, rows: 30}

    check all(
            t <- one_of([float(min: 0.0, max: 120.0), float(min: 120.0, max: 1.0e6)]),
            max_runs: 60
          ) do
      {fast, _, _} = Fern.frame(state, t, env)

      assert IO.iodata_to_binary(fast) == IO.iodata_to_binary(Fern.exact_frame(state, t)),
             "differs at t=#{t}"
    end
  end
end
