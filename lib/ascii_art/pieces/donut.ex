defmodule AsciiArt.Pieces.Donut do
  @moduledoc """
  A lit torus turning on two axes, after donut.c.

  A torus turning on two axes, lit from the upper left. After Andy Sloane's
  donut.c, with the ring sized so it never clips at any angle.

  Ported from `src/pieces/donut.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "donut",
    category: :shapes,
    note: "a lit torus turning on two axes, after donut.c",
    cols: 40,
    rows: 22,
    fps: 30
  }

  @ramp {".", ",", "-", "~", ":", ";", "=", "!", "*", "#", "$", "@"}
  # Tube radius, ring radius, eye to centre; a cell is about twice as tall as it is wide.
  @r1 1
  @r2 2
  @k2 6
  @aspect 0.5

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols} = @meta
    k1 = (cols - 2) / 2 / ((@r1 + @r2) / :math.sqrt(@k2 * @k2 - :math.pow(@r1 + @r2, 2)))
    m = JSMath.hypot(-0.4, 1, -1)

    # The angles the loops step through, accumulated as JS adds them.
    steps = fn step -> Stream.iterate(0, &(&1 + step)) |> Enum.take_while(&(&1 < 6.283)) end
    ths = for th <- steps.(0.07), do: {:math.cos(th), :math.sin(th)}
    phs = for ph <- steps.(0.03), do: {:math.cos(ph), :math.sin(ph)}

    %{k1: k1, k1a: k1 * @aspect, light: {-0.4 / m, 1 / m, -1 / m}, ths: ths, phs: phs}
  end

  @impl true
  def frame(state, t, env) do
    %{cols: cols, rows: rows} = @meta
    %{k1: k1, k1a: k1a, light: {lx, ly, lz}} = state
    a = 1 + t * 0.8
    b = 1 + t * 0.35
    ca = :math.cos(a)
    sa = :math.sin(a)
    cb = :math.cos(b)
    sb = :math.sin(b)
    sa_sb = sa * sb
    sa_cb = sa * cb
    half_cols = cols / 2
    half_rows = rows / 2
    last = tuple_size(@ramp) - 1

    cells =
      Enum.reduce(state.ths, %{}, fn {ct, st}, acc ->
        h = @r2 + @r1 * ct
        st_ca_sb = @r1 * st * ca * sb
        st_ca_cb = @r1 * st * ca * cb
        st_sa = @r1 * st * sa
        ca_h = ca * h
        ca_ct = ca * ct

        Enum.reduce(state.phs, acc, fn {cp, sp}, acc ->
          u = cb * cp + sa_sb * sp
          v = sb * cp - sa_cb * sp
          x = h * u - st_ca_sb
          y = h * v + st_ca_cb
          ooz = 1 / (@k2 + ca_h * sp + st_sa)
          col = floor(half_cols + k1 * ooz * x)
          row = floor(half_rows - k1a * ooz * y)
          k = col + row * cols

          cond do
            col < 0 or col >= cols or row < 0 or row >= rows ->
              acc

            match?(%{^k => {d, _}} when ooz <= d, acc) ->
              acc

            true ->
              # The surface normal is the same rotation applied to the tube's circle.
              nx = ct * u - st_ca_sb
              ny = ct * v + st_ca_cb
              nz = ca_ct * sp + st * sa
              i = JSMath.round(max(0, nx * lx + ny * ly + nz * lz) * last)

              Map.put(
                acc,
                k,
                {JSMath.fround(ooz), elem(@ramp, if(env.paper, do: last - i, else: i))}
              )
          end
        end)
      end)

    lines = for r <- 0..(rows - 1), do: for(c <- 0..(cols - 1), do: cell(cells, c + r * cols))

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(cells, k) do
    case cells do
      %{^k => {_, ch}} -> ch
      _ -> " "
    end
  end
end
