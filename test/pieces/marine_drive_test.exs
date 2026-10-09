defmodule Ascii.Pieces.MarineDriveTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.MarineDrive
  use Ascii.GoldenCase, slug: "marine-drive", piece: Ascii.Pieces.MarineDrive

  alias Ascii.Pieces.MarineDrive, as: Piece

  # With the fast paths off (the memo, the power's bounds, the skipped
  # glint) the same times must draw the same frames and colours, the memo
  # and the colour cache evolving through each run.
  property "the fast paths draw what the exact path draws" do
    check all(times <- times(), color? <- boolean(), max_runs: 50) do
      state = Ascii.TestCache.fetch({:init, Piece}, fn -> Piece.init(Piece.meta().options) end)
      fast = play(state, times, color?)
      exact = play(%{state | exact?: true}, times, color?)
      at = Enum.find_index(Enum.zip(fast, exact), fn {a, b} -> a != b end)

      assert at == nil,
             "fast and exact differ at t=#{Enum.at(times, at || 0)} (colour: #{color?})"
    end
  end

  # A start, then steps: some a frame apart, so the memo is used.
  defp times do
    gen all(
          start <- float(min: 0.0, max: 120.0),
          steps <-
            list_of(
              one_of([constant(1 / 15), float(min: 0.0, max: 0.3), float(min: 0.0, max: 20.0)]),
              min_length: 1,
              max_length: 4
            )
        ) do
      Enum.scan([start | steps], &(&1 + &2))
    end
  end

  defp play(state, times, color?) do
    meta = Piece.meta()
    env = %Ascii.Env{cols: meta.cols, rows: meta.rows, color?: color?}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, colors, state} = Piece.frame(state, t, env)
        {{IO.iodata_to_binary(io), colors}, state}
      end)

    frames
  end
end
