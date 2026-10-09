defmodule Ascii.Pieces.Tunnel do
  @moduledoc """
  Flying down a tiled tube that bends and twists.

  The demo-scene tunnel. Each cell casts a ray down a tiled tube that bends
  away out of sight, so the far end swings about, while the tiles wind round
  it in a slow spiral and fade into the dark.

  Ported from `src/pieces/tunnel.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "tunnel",
    category: :effects,
    note: "flying down a tiled tube that bends and twists",
    cols: 64,
    rows: 24,
    fps: 30
  }

  @cols 64
  @rows 24
  @ramp {" ", ".", ",", ":", ";", "-", "=", "+", "*", "#", "%", "@"}
  @last 11
  # Focal length, in columns.
  @f 18
  # Tiles round the tube, and per unit of depth.
  @around 10
  @along 0.55
  # The dark tiles' share of the light ones, and the mortar's.
  @dim 0.35
  @mortar 0.1
  # The most of a tile the mortar takes on each side.
  @gap 0.07
  # Units of depth a second.
  @speed 2.4
  # Turns of the tile pattern per unit of depth.
  @twist 0.06
  # Depth over which light falls by e.
  @fog 2.8
  # Depth over which the tube turns toward its far heading.
  @bend 3
  # How much a lamp to the upper left favours the far wall.
  @key 0.12
  # Share of a cell's footprint the pattern is averaged over.
  @sharp 0.7
  @tau 2 * :math.pi()
  @sqrt1_2 0.7071067811865476
  @gu_scale 4 * :math.pi() * 18

  @compile {:inline, wrap: 1, wave: 2, ridge: 2, pulse: 3, turn: 1}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # One sample more right and below, for each cell's footprint: each ray's
    # direction on screen and the depth it starts its search from.
    rays =
      for r <- 0..@rows do
        sy = -((r + 0.5 - @rows / 2) * 2) / @f

        for c <- 0..@cols do
          sx = (c + 0.5 - @cols / 2) / @f
          {sx, sy, 1 / max(1.0e-3, JSMath.hypot(sx, sy))}
        end
      end

    %{rays: rays}
  end

  # A square wave, and pulses of half-width g at the whole numbers, each
  # averaged over a span w, so tiles smaller than a cell fade to an even grey.
  defp wrap(x), do: x - floor(x)

  defp wave(x, w),
    do: 2 * (abs(wrap((x - w / 2) / 2) - 0.5) - abs(wrap((x + w / 2) / 2) - 0.5)) / w

  defp ridge(x, g), do: floor(x + g) * 2 * g + min(wrap(x + g), 2 * g)
  defp pulse(x, w, g), do: (ridge(x + w / 2, g) - ridge(x - w / 2, g)) / w

  # Going round, the seam is no jump.
  defp turn(d), do: d - @around * JSMath.round(d / @around)

  @impl true
  def frame(%{rays: rays} = state, t, env) do
    # Where the far end points, as a slope off the view axis, on a slow loop.
    ax = 0.42 * :math.sin(t * 0.55)
    ay = 0.26 * :math.sin(t * 0.9 + 1)
    spin = t * 0.06
    drift = t * @speed * @along

    samples = Enum.map(rays, fn row -> Enum.map(row, &sample(&1, ax, ay, spin, drift)) end)

    lines =
      samples
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [row, below] -> cells(row, below, env.paper) end)

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A ray hits the wall (radius 1) at the depth z where its offset from the
  # bent axis is 1. Solve by iteration: the axis at depth z leans toward
  # (ax, ay) by a share that grows with z.
  defp sample({sx, sy, z}, ax, ay, spin, drift) do
    {dx, dy, z} = lean(sx, sy, z, ax, ay, 4)
    u = (:math.atan2(dy, dx) / @tau + spin + z * @twist) * @around
    v = z * @along + drift
    # Light falls off down the tube, and the wall facing the lamp is brighter.
    l = :math.exp(-z / @fog) * (1 - @key + @key * (dx - dy) * z * @sqrt1_2)
    {u, v, z, l}
  end

  defp lean(sx, sy, z, _ax, _ay, 0), do: {sx, sy, z}

  defp lean(sx, sy, z, ax, ay, n) do
    lean = 1 - :math.exp(-z / @bend)
    dx = sx - ax * lean
    dy = sy - ay * lean
    z = min(60.0, 1 / max(1.0e-3, JSMath.hypot(dx, dy)))
    if n == 1, do: {dx, dy, z}, else: lean(sx, sy, z, ax, ay, n - 1)
  end

  defp cells([{u, v, z, l} | [{u1, v1, _, _} | _] = rest], [{u2, v2, _, _} | below], paper) do
    # How far the pattern moves across this cell, in tiles.
    wu = @sharp * max(max(abs(turn(u1 - u)), abs(turn(u2 - u))), 0.01)
    wv = @sharp * max(max(abs(v1 - v), abs(v2 - v)), 0.01)
    # Light tiles and dark ones, set in mortar lines kept about a cell
    # wide on screen however near or far they are.
    light = 0.5 - 0.5 * wave(u, wu) * wave(v, wv)
    gu = min(@gap, z * @around / @gu_scale)
    gv = min(@gap, z * z * @along / @f)
    mortar = 1 - (1 - pulse(u, wu, gu)) * (1 - pulse(v, wv, gv))
    b = ((@dim + (1 - @dim) * light) * (1 - mortar) + @mortar * mortar) * l * 1.25
    i = min(@last, JSMath.round(:math.pow(max(0, b), 0.8) * @last))
    [elem(@ramp, if(paper, do: @last - i, else: i)) | cells(rest, below, paper)]
  end

  defp cells([_last], [_], _paper), do: []
end
