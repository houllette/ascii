defmodule AsciiArt.Pieces.Rotozoomer do
  @moduledoc """
  A brick wall texture turning and zooming about the centre.

  The demo-scene classic. A wall of bevelled bricks set in deep mortar,
  turned and scaled about the middle of the screen every frame.

  Ported from `src/pieces/rotozoomer.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  import Bitwise

  @meta %AsciiArt.Meta{
    name: "rotozoomer",
    category: :effects,
    note: "a brick wall texture turning and zooming about the centre",
    cols: 64,
    rows: 24,
    fps: 30,
    loop: 16
  }

  @cols 64
  @rows 24

  # One shade for each surface of the wall, as in text-mode demos: mortar,
  # shadowed bevel, brick face, side-lit bevel, top-lit bevel.
  @shades {" ", "░", "▒", "▓", "█"}
  # Seconds for one full turn; the zoom and the drift repeat in it.
  @p 16
  @w 2 * :math.pi() / 16
  # Half the mortar joint, and the bevel width, in brick heights.
  @m 0.085
  @b 0.15
  @face 0.66
  @mortar 0.02
  # Top, left, right and bottom bevels: lit from the upper left.
  @edge_top 1.0
  @edge_left 0.86
  @edge_right 0.3
  @edge_bottom 0.22
  @tw 2 - 2 * 0.085
  @th 1 - 2 * 0.085

  # Nine samples to a cell, in cell widths from its centre, rows counted
  # double: three across (by column) and three down (by row).
  @sx [(0 - 1) / 3, (1 - 1) / 3, (2 - 1) / 3]
  @sy [(0 - 1) / 3 * 2, (1 - 1) / 3 * 2, (2 - 1) / 3 * 2]

  @compile {:inline, tex: 2, shade: 2}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # Each sample's offset from the middle, across for every column and down
    # for every row, as upstream adds them.
    xs = for c <- 0..(@cols - 1), do: for(s <- @sx, do: c + 0.5 - @cols / 2 + s)
    ys = for r <- 0..(@rows - 1), do: for(s <- @sy, do: (r + 0.5 - @rows / 2) * 2 + s)
    %{xs: xs, ys: ys}
  end

  # Brightness at (u, v), in brick heights; a brick is two long and every other
  # course is set half a brick over.
  defp tex(u, v) do
    iv = floor(v)
    x = u + band(iv, 1)
    lx = x - 2 * floor(x / 2) - @m
    ly = v - iv - @m

    if lx < 0 or ly < 0 or lx > @tw or ly > @th do
      @mortar
    else
      rx = @tw - lx
      by = @th - ly
      e = min(min(min(ly, lx), rx), by)

      cond do
        e > @b -> @face
        e == ly -> @edge_top
        e == lx -> @edge_left
        e == rx -> @edge_right
        true -> @edge_bottom
      end
    end
  end

  @impl true
  def frame(%{xs: xs, ys: ys} = state, t, env) do
    # The turn lingers where the courses run square to the screen.
    th = @w * t + 0.08
    a = th - 0.14 * :math.sin(4 * th)
    # Brick height, in cell widths.
    l = 13 * :math.exp(0.25 * :math.cos(2 * @w * t))
    ca = :math.cos(a) / l
    sa = :math.sin(a) / l
    # The wall drifts two bricks along and two courses up a loop, so it closes.
    u0 = 4 * t / @p + 0.7 * :math.sin(@w * t) + 0.35
    v0 = 2 * t / @p + 0.7 * :math.cos(@w * t) - 0.2

    # px * ca and px * sa for every column's samples, py * sa and py * ca for
    # every row's: the same products upstream takes per sample.
    cols = for [x0, x1, x2] <- xs, do: {x0 * ca, x1 * ca, x2 * ca, x0 * sa, x1 * sa, x2 * sa}

    lines =
      for [y0, y1, y2] <- ys do
        a0 = y0 * sa
        a1 = y1 * sa
        a2 = y2 * sa
        b0 = y0 * ca
        b1 = y1 * ca
        b2 = y2 * ca

        for {c0, c1, c2, s0, s1, s2} <- cols do
          v =
            tex(c0 + a0 + u0, b0 - s0 + v0) + tex(c1 + a0 + u0, b0 - s1 + v0) +
              tex(c2 + a0 + u0, b0 - s2 + v0) + tex(c0 + a1 + u0, b1 - s0 + v0) +
              tex(c1 + a1 + u0, b1 - s1 + v0) + tex(c2 + a1 + u0, b1 - s2 + v0) +
              tex(c0 + a2 + u0, b2 - s0 + v0) + tex(c1 + a2 + u0, b2 - s1 + v0) +
              tex(c2 + a2 + u0, b2 - s2 + v0)

          shade(v / 9, env.paper)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp shade(v, paper) do
    i =
      cond do
        v <= 0.12 -> 0
        v <= 0.44 -> 1
        v <= 0.78 -> 2
        v <= 0.93 -> 3
        true -> 4
      end

    elem(@shades, if(paper, do: 4 - i, else: i))
  end
end
