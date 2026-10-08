defmodule AsciiArt.Pieces.VaranasiGhatsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.VaranasiGhats
  use AsciiArt.GoldenCase, slug: "varanasi-ghats", piece: AsciiArt.Pieces.VaranasiGhats

  alias AsciiArt.Env
  alias AsciiArt.Pieces.VaranasiGhats

  # The frame's shortcuts (`:math` checked against margins, precomputed dots,
  # rows and columns no light reaches passed over) must draw exactly what the
  # forced exact path draws, colour cache included, at any times in any order.
  property "the shortcuts draw what the exact path draws" do
    state =
      AsciiArt.TestCache.fetch({:init, VaranasiGhats}, fn ->
        VaranasiGhats.init(VaranasiGhats.meta().options)
      end)

    check all(
            times <- list_of(float(min: 0.0, max: 120.0), min_length: 1, max_length: 3),
            color? <- boolean(),
            max_runs: 40
          ) do
      env = %Env{cols: 200, rows: 100, color?: color?}
      {fast, fast_state} = play(state, times, env)
      {exact, exact_state} = play(%{state | exact?: true}, times, env)

      for {{t, a}, {t, b}} <- Enum.zip(fast, exact) do
        assert a == b, "frames differ at t=#{t} (colour: #{color?}, times: #{inspect(times)})"
      end

      assert fast_state.lut == exact_state.lut
    end
  end

  defp play(state, times, env) do
    Enum.map_reduce(times, state, fn t, state ->
      {io, colors, state} = VaranasiGhats.frame(state, t, env)
      {{t, {IO.iodata_to_binary(io), colors}}, state}
    end)
  end
end
