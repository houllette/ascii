defmodule AsciiArt.Pieces.PendulumWave do
  @moduledoc """
  A row of pendulums drifting in and out of step, from above.

  A row of pendulums seen from above, hung from one rail. Bob n swings 60 + n
  times every 150 seconds, so the row drifts from one wave into two, three, a
  braid and a zigzag, then lines up again once a cycle.

  Ported from `src/pieces/pendulum-wave.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "pendulum wave",
    category: :physics,
    note: "a row of pendulums drifting in and out of step, from above",
    cols: 67,
    rows: 19,
    fps: 30,
    loop: 150
  }

  # Bobs, and columns from one bob to the next.
  @n 21
  @gap 3
  # Seconds until every bob lines up again, and swings the slowest bob makes
  # in one cycle.
  @cycle 150
  @base 60
  # Seconds of motion blur behind each bob.
  @blur 0.07
  # A wave and a half across the row.
  @t0 1.5 * @cycle / (@n - 1)

  @cols 67
  @rows 19
  @left div(@cols - (@n - 1) * @gap - 1, 2)
  # The rail, straight above every bob at rest.
  @mid div(@rows - 1, 2)
  @right @left + (@n - 1) * @gap

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options), do: nil

  # The swing spans every row but the first and last.
  defp row(n, t),
    do: 1 + (1 - :math.cos(2 * :math.pi() * (@base + n) * t / @cycle)) * (@rows - 3) / 2

  # The rail runs the length of the row, a little past each end.
  defp rail(c) when c == @left - 1, do: "╶"
  defp rail(c) when c == @right + 1, do: "╴"
  defp rail(c) when c > @left - 1 and c < @right + 1, do: "─"
  defp rail(_c), do: " "

  @impl true
  def frame(state, time, _env) do
    t = time + @t0

    out =
      Enum.reduce(0..(@n - 1), %{}, fn n, out ->
        c = @left + n * @gap
        now = JSMath.round(row(n, t))
        # The cells the bob crossed in the last instant smear into a faint
        # streak; the rail shows through it.
        thn = JSMath.round(row(n, t - @blur))
        {a, b} = if now < thn, do: {now + 1, thn}, else: {thn, now - 1}

        out =
          for r <- a..b//1, r != @mid, reduce: out do
            out -> Map.put(out, r * @cols + c, if(abs(r - now) == 1, do: ":", else: "·"))
          end

        Map.put(out, now * @cols + c, "o")
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          Map.get_lazy(out, r * @cols + c, fn -> if r == @mid, do: rail(c), else: " " end)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
