defmodule AsciiArt.Pieces.Plasma do
  @moduledoc """
  Soft interference blobs drifting and pulsing.

  The old demo-scene effect. Four sine fields, one a set of rings round a
  wandering centre, summed and read as soft blobs of density.

  Ported from `src/pieces/plasma.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "plasma",
    category: :generative,
    note: "soft interference blobs drifting and pulsing",
    cols: 64,
    rows: 22,
    fps: 24,
    loop: 30
  }

  @ramp {".", ",", "-", "~", ":", ";", "=", "+", "*", "#", "%", "@"}
  # Seconds; every term turns a whole number of times in one loop.
  @p 30
  # Ramp sweeps per unit of the summed field: low, so the blobs are broad.
  @gain 0.32

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta

    # Cell centres in cell widths, the rows stretched to their true height.
    %{
      xs: for(c <- 0..(cols - 1), do: JSMath.fround(c + 0.5 - cols / 2)),
      ys: for(r <- 0..(rows - 1), do: JSMath.fround((r + 0.5 - rows / 2) * 2)),
      w: 2 * :math.pi() / @p
    }
  end

  @impl true
  def frame(%{xs: xs, ys: ys, w: w} = state, t, env) do
    a = w * t
    ca = :math.cos(a)
    sa = :math.sin(a)
    # The rings' centre.
    cx = 14 * sa
    cy = 9 * :math.cos(2 * a)
    drift = a / :math.pi()
    a4 = 4 * a
    a5 = 5 * a
    n = tuple_size(@ramp)

    # The first field only changes across, the second only down.
    across = for x <- xs, do: {:math.sin(x * 0.11 + 3 * a), x * ca, x - cx}

    lines =
      for y <- ys do
        down = :math.sin(y * 0.13 - 2 * a)
        ysa = y * sa
        dy = y - cy

        for {s1, xca, dx} <- across do
          v = s1 + down
          v = v + :math.sin((xca + ysa) * 0.09 + a4)
          v = v + :math.sin(JSMath.hypot(dx, dy) * 0.17 - a5)
          # Up the ramp and back down, evenly, drifting through it once a loop.
          u = v * @gain + drift
          k = abs(u - 2 * floor(u / 2 + 0.5))
          i = min(n - 1, floor(k * n))
          elem(@ramp, if(env.paper, do: n - 1 - i, else: i))
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
