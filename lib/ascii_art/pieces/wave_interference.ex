defmodule AsciiArt.Pieces.WaveInterference do
  @moduledoc """
  Two sources in a ripple tank, still lines fanning out.

  Two dippers in a round ripple tank, seen from above. Where their waves
  cancel the water lies still, and those calm lines fan out and swing as the
  dippers drift.

  `wavelength` is in rows (a column is half a row); `separation` is how many
  wavelengths apart the dippers sit.

  Ported from `src/pieces/wave-interference.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "wave interference",
    category: :physics,
    note: "two sources in a ripple tank, still lines fanning out",
    cols: 72,
    rows: 26,
    fps: 24,
    options: %{wavelength: 5, separation: 2.2},
    bounds: %{wavelength: {0, 100}, separation: {-20, 20}}
  }

  # Troughs run dark through to calm water at ":", crests bright above it; a
  # short ramp keeps each band bold.
  @ramp {" ", ".", ":", "=", "*", "#"}
  @calm 2
  # Seconds per wave.
  @period 1

  @cols 72
  @rows 26
  # The tank's middle, in rows, and its half width and height.
  @cx @cols / 4
  @cy @rows / 2
  @a @cx - 0.6
  @b @cy - 0.4

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{wavelength: wavelength, separation: separation}) do
    lam = max(3, wavelength)

    # The water, cell by cell: where it is, and how much the shallows by the
    # rim calm it; nil outside the tank.
    water =
      for r <- 0..(@rows - 1), c <- 0..(@cols - 1) do
        x = (c + 0.5) / 2
        y = r + 0.5
        q = JSMath.hypot((x - @cx) / @a, (y - @cy) / @b)

        if q >= 1 do
          nil
        else
          calm = min(1, (1 - q) / 0.2)
          {x, y, calm, 3 - 2 * calm}
        end
      end

    %{lam: lam, k: 2 * :math.pi() / lam, separation: separation, water: water}
  end

  @impl true
  def frame(%{lam: lam, k: k} = state, t, %{paper: paper}) do
    w = 2 * :math.pi() * t / @period

    # The dippers drift apart and together and their axis rocks; both repeat
    # within 90 seconds.
    half =
      min(
        @b - 1.5,
        lam * abs(state.separation) * (1 + 0.2 * :math.sin(2 * :math.pi() * t / 30)) / 2
      )

    tilt = 0.25 * :math.sin(2 * :math.pi() * t / 45)
    st = :math.sin(tilt)
    ct = :math.cos(tilt)
    sx0 = @cx - half * st
    sx1 = @cx + half * st
    sy0 = @cy - half * ct
    sy1 = @cy + half * ct

    cells =
      state.water
      |> Enum.map(fn
        nil ->
          " "

        {x, y, calm, edge} ->
          d1 = JSMath.hypot(x - sx0, y - sy0)
          d2 = JSMath.hypot(x - sx1, y - sy1)
          a1 = 1 / :math.sqrt(1 + d1 * 0.1)
          a2 = 1 / :math.sqrt(1 + d2 * 0.1)

          # The surface height, out of the most two waves can give; the
          # shallows by the rim calm it.
          h =
            (a1 * :math.cos(k * d1 - w) + a2 * :math.cos(k * d2 - w)) / (a1 + a2) * calm *
              calm * edge

          h = if paper, do: -h, else: h

          i =
            if h < 0,
              do: JSMath.round(@calm * (1 + h)),
              else: JSMath.round(@calm + (tuple_size(@ramp) - 1 - @calm) * h)

          elem(@ramp, i)
      end)
      |> List.to_tuple()

    # Each dipper bobs in a little calm of its own.
    out =
      [{sx0, sy0}, {sx1, sy1}]
      |> Enum.reduce(%{}, fn {sx, sy}, out ->
        at = floor(sy) * @cols + floor(sx * 2)
        out |> Map.put(at - 1, " ") |> Map.put(at + 1, " ") |> Map.put(at, "O")
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          i = r * @cols + c
          Map.get_lazy(out, i, fn -> elem(cells, i) end)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
