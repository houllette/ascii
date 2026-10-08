defmodule AsciiArt.Pieces.TajDawn do
  @moduledoc """
  The taj mahal at sunrise, mirrored in its pool through morning haze.

  The Taj Mahal at first light, seen down its long reflecting canal between
  rows of cypress. The sun has just cleared the red sandstone mosque on the
  left; the haze and the clouds drift, the canal's reflection ripples, light
  glints along its far end, and a few birds cross.

  Shaded in colour cell by cell, then drawn as a halftone: each cell is a dot
  sized by its brightness, ordered-dithered, in the palette colour nearest
  its hue, with the colour brightened or dimmed to make up for the dot's
  size.

  Ported from `src/pieces/taj-dawn.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "taj dawn",
    category: :scenes,
    note: "the taj mahal at sunrise, mirrored in its pool through morning haze",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#0d0a13",
    palette: [
      "#2e2a55",
      "#3d3870",
      "#514a8a",
      "#6a62a3",
      "#8a83bd",
      "#5a3a5e",
      "#7a4d72",
      "#9a6284",
      "#b97a92",
      "#d495a2",
      "#b8705a",
      "#d98d66",
      "#efab78",
      "#f8c98e",
      "#ffe2ae",
      "#fff3d8",
      "#fffcf2",
      "#8e7f9e",
      "#ad9cb4",
      "#cbb6c4",
      "#e3cdd2",
      "#f3e0dc",
      "#2a4a3e",
      "#36584a",
      "#4a6c58",
      "#66845f",
      "#8a9a68",
      "#8a4a3e",
      "#b0624a",
      "#3a2f4a",
      "#4e3d5a",
      "#f6d6c0",
      "#e9bfae",
      "#5e6a40",
      "#7d8a52",
      "#a3a064",
      "#c2b274"
    ]
  }

  @w 200
  @h 100
  # The Taj's axis, and the canal's vanishing point.
  @cx 128
  # Where the Taj meets the garden, and the far end of the canal.
  @base 68
  # Eye level.
  @hz 60
  # Cells per metre on the Taj.
  @s 0.7
  @sun_x 36
  @sun_y 40
  # The mosque's axis and foot.
  @mx 45
  @mb 67
  # The reflection is foreshortened so the dome reaches the canal.
  @kr 1.55
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  # Materials.
  @sky 0
  @bgtree 1
  @marble 2
  @lawn 3
  @walk 4
  @pool 5
  @cypress 6
  @mosque 7

  # The drifting cloud strip and the haze strip, both wrapping.
  @cw 400
  @ch 50
  @hwd 400
  # Dawn cloud: {x, y, half-width, height above, depth below, strength}.
  @banks [
    # Over the sun's right shoulder.
    {76, 28, 40, 7, 3.5, 1.4},
    # Behind the dome.
    {152, 36, 52, 9, 4, 1},
    # A high wisp.
    {16, 13, 32, 4, 2.5, 0.8},
    {250, 24, 40, 8, 4, 1},
    {330, 33, 36, 7, 4, 0.95}
  ]

  @impl true
  def meta, do: @meta

  @compile {:inline, clamp: 1, smooth: 3, mix: 3, fround: 1, cube: 1, round_js: 1}
  defp clamp(v) when v < 0, do: 0
  defp clamp(v) when v > 1, do: 1
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  defp fround(x), do: JSMath.fround(x)

  # `JSMath.round/1`, here so that it inlines.
  defp round_js(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  defp noise(x, y, period), do: Scene.noise(x, y, period)
  defp fbm(x, y, octaves, period), do: Scene.fbm(x, y, octaves, period)
  defp hash(x, y), do: Hash.scene(x, y)

  # The onion dome's profile: swelling out past the drum, then drawn to a
  # point.
  defp onion(h) when h < 0.3, do: 0.8 + 0.2 * :math.sin(h / 0.3 * :math.pi() * 0.5)
  defp onion(h), do: :math.pow(:math.cos((h - 0.3) / 0.7 * :math.pi() * 0.5), 1.45)

  # Pointed arch: half-width at height h above the springline, for an arch
  # of half-width w; zero above the apex.
  defp arch(w, h) when h <= 0, do: w

  defp arch(w, h) do
    c = w * 0.5
    r = w + c
    q = r * r - h * h
    if q > 0, do: max(0, :math.sqrt(q) - c), else: 0
  end

  # --- the Taj -----------------------------------------------------------

  # The Taj in metres: X across from the axis, Y up from the garden, as
  # {lit, recess} for marble or nil for air. lit runs 0 (shadow, facing away
  # from the sun) to 1 (facing it); recess darkens arches and niches. Each
  # part is tried in turn, as upstream's chain of returns.
  defp taj(xx, yy) do
    ax = abs(xx)
    # +1 on the sun's side.
    left = if xx < 0, do: 1, else: -1
    s = {xx, yy, ax, left}

    Enum.reduce_while(
      [
        &finial/1,
        &great_dome/1,
        &chhatri/1,
        &drum/1,
        &pinnacle/1,
        &building/1,
        &minaret/1,
        &plinth/1
      ],
      nil,
      fn part, nil ->
        case part.(s) do
          :none -> {:cont, nil}
          hit -> {:halt, hit}
        end
      end
    )
  end

  defp finial({_xx, yy, ax, left}) do
    bulge =
      0.75 + if(abs(yy - 74.5) < 0.9, do: 0.6, else: 0) + if(abs(yy - 77) < 0.7, do: 0.4, else: 0)

    if yy >= 72 and yy < 80.5 and ax <= bulge, do: {0.75 + 0.2 * left, 0}, else: :none
  end

  # The great dome: a sphere lit from the left and a little above.
  defp great_dome({xx, yy, ax, _left}) when yy >= 47.5 and yy < 72 do
    h = (yy - 47.5) / 24.5
    hw = 15 * onion(h)

    if ax <= hw do
      nx = xx / (hw + 0.01)
      nz = :math.sqrt(max(0, 1 - nx * nx))
      {clamp(0.3 + 0.5 * (-0.8 * nx + 0.4 * nz) + 0.2 * h), 0}
    else
      :none
    end
  end

  defp great_dome(_s), do: :none

  # The four chhatris on the roof, two in view.
  defp chhatri({xx, yy, ax, left}) do
    cx = ax - 17.5

    if abs(cx) <= 4.4 and yy >= 39.5 and yy < 55.5 do
      sx = if xx < 0, do: -cx, else: cx
      chhatri(cx, sx, sx / 4.4, yy, left)
    else
      :none
    end
  end

  defp chhatri(_cx, _sx, nx, yy, left) when yy < 41, do: {clamp(0.5 - 0.4 * nx * left), 0}

  defp chhatri(cx, sx, _nx, yy, left) when yy < 46.5 do
    if abs(cx) > 3.6 do
      nil
    else
      open = abs(cx) < 2.6 and abs(cx) > 0.6 and yy < 45.5
      {clamp(0.5 - 0.45 * sx / 4 * left), if(open, do: 0.75, else: 0)}
    end
  end

  defp chhatri(_cx, _sx, nx, yy, left) when yy < 47.3, do: {clamp(0.55 - 0.4 * nx * left), 0}

  defp chhatri(cx, sx, _nx, yy, left) do
    h = (yy - 47.3) / 6.5

    cond do
      h < 1 and abs(cx) <= 4 * onion(h) ->
        {clamp(0.55 - 0.6 * (sx / (4 * onion(h) + 0.01)) * left + 0.1 * h), 0}

      h >= 1 and abs(cx) < 0.6 ->
        {0.6, 0}

      true ->
        :none
    end
  end

  # The drum under the dome.
  defp drum({xx, yy, ax, _left}) when yy >= 40 and yy < 47.5 and ax <= 12.2 do
    nx = xx / 12.2
    band = if yy > 45.8, do: 0.15, else: 0
    {clamp(0.45 - 0.55 * nx + band), 0}
  end

  defp drum(_s), do: :none

  # Slender pinnacles at the corners of the portal and of the building.
  defp pinnacle({_xx, yy, ax, left}) do
    if (abs(ax - 8.8) < 0.75 and yy >= 40 and yy < 47.5) or
         (abs(ax - 28.2) < 0.75 and yy >= 38 and yy < 44.5),
       do: {0.55 + 0.25 * left, 0},
       else: :none
  end

  # The main building; the portal rises a little above the parapet.
  defp building({_xx, yy, ax, left}) when ax <= 28.5 and yy >= 7 and yy < 40 do
    cond do
      yy >= 38.5 and ax > 9 and band(floor((ax + 0.5) / 1.5), 1) == 1 -> nil
      ax <= 9 -> portal(yy, ax, left)
      ax <= 21 -> front(yy, ax, left)
      true -> corner(yy, ax, left)
    end
  end

  defp building(_s), do: :none

  # The central portal: a calligraphy band round a deep pointed arch.
  defp portal(yy, ax, left) do
    hw = arch(6, yy - 25)

    cond do
      ax <= hw and yy < 25 + 9 ->
        door = ax <= 3.2 and ax <= arch(3.2, yy - 15.5)
        {0.35 + 0.15 * left, if(door, do: 0.82, else: 0.6 + 0.12 * (1 - smooth(25, 33, yy)))}

      ax <= hw + 0.8 and yy < 25 + 10.2 ->
        {0.42, 0.35}

      ax > 7.6 and ax <= 9 and yy < 40 ->
        {0.5 + 0.12 * left, 0.08}

      true ->
        {0.5 + 0.08 * left, 0}
    end
  end

  # The front face either side of the portal: two storeys of arched niches.
  defp front(yy, ax, left) do
    nx = ax - 15

    Enum.find_value([{9, 21.5}, {24.5, 37}], {0.5 + 0.1 * left, 0}, fn {y0, y1} ->
      cond do
        yy >= y0 and yy < y1 and abs(nx) <= arch(3.6, yy - (y1 - 4.5)) ->
          {0.4 + 0.1 * left, 0.5}

        yy >= y0 - 0.6 and yy < y1 + 0.6 and abs(nx) <= arch(4.3, yy - (y1 - 4.2)) and
            abs(nx) > 3.6 ->
          {0.45, 0.22}

        true ->
          nil
      end
    end)
  end

  # Chamfered corners, turned toward the sun on the left and away on the
  # right.
  defp corner(yy, ax, left) do
    lit = 0.5 + 0.48 * left
    nx = ax - 24.7

    Enum.find_value([{9, 21.5}, {24.5, 37}], {lit, 0}, fn {y0, y1} ->
      if yy >= y0 and yy < y1 and abs(nx) <= arch(2.2, yy - (y1 - 3)), do: {lit * 0.7, 0.45}
    end)
  end

  # Minarets at the corners of the plinth, tapering, with three galleries.
  defp minaret({xx, yy, ax, left}) when yy >= 7 and yy < 57 do
    mx = ax - 44
    # Across the shaft, toward the sun negative.
    s = if xx < 0, do: -mx, else: mx
    hw = 2.9 - 0.6 * (yy - 7) / 40

    gallery =
      Enum.find_value([19.5, 32, 44.5], fn g ->
        if yy >= g and yy < g + 1.4 and abs(mx) <= hw + 1.1,
          do: {clamp(0.5 - 0.42 * s / (hw + 1.1) * left), if(yy < g + 0.5, do: 0.35, else: 0)}
      end)

    cond do
      gallery != nil ->
        gallery

      yy < 46 and abs(mx) <= hw ->
        {clamp(0.5 - 0.48 * (s / hw) * left), 0}

      yy >= 45.9 and yy < 49.5 and abs(mx) <= 2.2 ->
        {clamp(0.5 - 0.4 * s / 2.2 * left), if(abs(mx) < 1.4 and abs(mx) > 0.3, do: 0.7, else: 0)}

      yy >= 49.5 ->
        minaret_top(yy, mx, s, left)

      true ->
        :none
    end
  end

  defp minaret(_s), do: :none

  defp minaret_top(yy, mx, s, left) do
    h = (yy - 49.5) / 4.5

    cond do
      h < 1 and abs(mx) <= 2.5 * onion(h) ->
        {clamp(0.55 - 0.55 * s / (2.5 * onion(h) + 0.01) * left), 0}

      h >= 1 and yy < 56 and abs(mx) < 0.5 ->
        {0.6, 0}

      true ->
        :none
    end
  end

  # The plinth, with a row of shallow niches.
  defp plinth({_xx, yy, ax, _left}) when ax <= 47.5 and yy >= 0 and yy < 7 do
    k = JSMath.mod(ax, 5.2) - 2.6

    cond do
      yy > 6.2 -> {0.62, 0}
      yy > 1.5 and yy < 5.2 and abs(k) < 1.1 -> {0.42, 0.3}
      true -> {0.52, 0}
    end
  end

  defp plinth(_s), do: nil

  # --- the mosque ----------------------------------------------------------

  # The red sandstone mosque that flanks the Taj, in cells: three domes over
  # a five-bay front with a tall central portal. 0 for wall, 1 for dome, 2
  # for a recess, -1 for air. It stands against the sun, so it is mostly
  # silhouette. Each part is tried in turn.
  defp mosque(xc, y) do
    ax = abs(xc - @mx)
    s = {xc, y, ax, abs(ax - 19.5), abs(ax - 11.5)}

    Enum.find_value(
      [&mosque_towers/1, &mosque_portal/1, &mosque_front/1, &mosque_domes/1],
      -1,
      & &1.(s)
    )
  end

  # The plinth, and the end towers, each with a small kiosk on top.
  defp mosque_towers({_xc, y, ax, tx, _sx}) do
    cond do
      y >= @mb - 2.5 and y < @mb and ax <= 22 -> 0
      tx <= 1.3 and y >= @mb - 13 and y < @mb - 2.5 -> 0
      y >= @mb - 15.5 and y < @mb - 13 and tx <= 1.8 * onion((@mb - 13 - y) / 2.5) -> 1
      tx < 0.35 and y >= @mb - 16.5 and y < @mb - 15.5 -> 1
      true -> nil
    end
  end

  # The central portal, rising above the front.
  defp mosque_portal({xc, y, ax, _tx, _sx}) when ax <= 5.5 and y >= @mb - 15 and y < @mb - 2.5 do
    cond do
      y < @mb - 14.3 and band(floor(xc), 1) == 1 -> -1
      ax <= arch(3.4, @mb - 9.5 - y) and y >= @mb - 13.5 -> 2
      true -> 0
    end
  end

  defp mosque_portal(_s), do: nil

  # The five-bay front and its parapet.
  defp mosque_front({xc, y, ax, _tx, _sx}) do
    cond do
      ax <= 18 and y >= @mb - 10 and y < @mb - 2.5 ->
        bay = JSMath.mod(ax - 5.5, 4.2) - 2.1
        if ax > 6 and y >= @mb - 8.5 and abs(bay) <= arch(1.4, @mb - 6.2 - y), do: 2, else: 0

      ax <= 18 and y >= @mb - 10.8 and y < @mb - 10 and band(floor(xc * 0.75), 1) == 1 ->
        0

      true ->
        nil
    end
  end

  # Side domes on drums, and the great central dome.
  defp mosque_domes({_xc, y, ax, _tx, sx}) do
    cond do
      sx <= 2.6 and y >= @mb - 12 and y < @mb - 10 -> 0
      y >= @mb - 17 and y < @mb - 12 and sx <= 3.6 * onion((@mb - 12 - y) / 5) -> 1
      sx < 0.35 and y >= @mb - 18.5 and y < @mb - 17 -> 1
      ax <= 4 and y >= @mb - 16.5 and y < @mb - 15 -> 0
      y >= @mb - 23.5 and y < @mb - 16.5 and ax <= 5.2 * onion((@mb - 16.5 - y) / 7) -> 1
      ax < 0.4 and y >= @mb - 25.5 and y < @mb - 23.5 -> 1
      true -> nil
    end
  end

  # --- the sky -------------------------------------------------------------

  defp sun_glow(x, y) do
    dx = x - @sun_x
    dy = (y - @sun_y) * 1.25
    d = :math.sqrt(dx * dx + dy * dy)
    :math.exp(-d / 4) * 0.9 + :math.exp(-d / 13) * 0.42 + :math.exp(-d / 40) * 0.3
  end

  defp sky_at(x, y) do
    v = clamp(y / @hz)
    # Deep violet overhead, mauve, then rose and peach toward the horizon.
    up = smooth(0.05, 0.8, v)
    {r, g, b} = {mix(0.055, 0.3, up), mix(0.05, 0.19, up), mix(0.17, 0.36, up)}
    low = smooth(0.62, 1, v)
    {r, g, b} = {mix(r, 0.66, low), mix(g, 0.4, low), mix(b, 0.42, low)}
    # Cooler and dimmer on the side away from the sun.
    far = smooth(50, 200, x) * 0.18
    {r, g, b} = {r * (1 - far), g * (1 - far * 0.8), b * (1 - far * 0.3)}

    glow =
      sun_glow(x, y) +
        :math.exp(-abs(y - 57) / 5) * 0.25 * :math.exp(-abs(x - @sun_x) / 50)

    {r, g, b} = {r + glow * 1.0, g + glow * 0.78, b + glow * 0.48}
    # Faint shafts of light fanning up from the sun through the haze.
    ang = :math.atan2(y - @sun_y, x - @sun_x)
    ray = fbm(ang * 9 + 3, 1.7, 2, 0)
    rd = JSMath.hypot(x - @sun_x, y - @sun_y)
    shaft = smooth(0.5, 0.75, ray) * :math.exp(-rd / 45) * smooth(4, 14, rd) * 0.12
    {r + shaft, g + shaft * 0.8, b + shaft * 0.55}
  end

  # Dawn cloud in a wrapping strip that drifts: broken noise, gathered into
  # a bank up and right of the sun and a lower one behind the dome.
  defp cdens(x, y) do
    q = fbm(x * 0.01, y * 0.04, 2, @cw * 0.01)
    n = fbm(x * 0.025 + q * 1.6, y * 0.075 + q * 0.6, 5, @cw * 0.025)

    m =
      Enum.reduce(@banks, 0, fn {bx, by, rx, up, down, a}, m ->
        dx = x - bx
        dx = dx - JSMath.round(dx / @cw) * @cw
        ex = dx / rx
        ey = (y - by) / if(y < by, do: up, else: down)
        e = :math.exp(-ex * ex * ex * ex - ey * ey) * a
        if e > m, do: e, else: m
      end)

    0.62 * m + 1.4 * (n - 0.5) + 0.02
  end

  # The cloud's cover and light, by row.
  defp clouds do
    rows =
      for r <- 0..(@ch - 1) do
        y = r + 0.5

        row =
          for x <- 0..(@cw - 1) do
            d = cdens(x, y)
            # The side toward the sun (down and left) catches the light.
            toward = cdens(x - 2, y + 2.5)

            lit =
              clamp(
                0.56 + (d - toward) * 0.75 - (d - 0.6) * 0.2 +
                  0.7 * (fbm(x * 0.09, y * 0.2, 2, @cw * 0.09) - 0.5)
              )

            {fround(smooth(0.46, 0.66, d)), fround(lit)}
          end

        {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
         row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
      end

    {rows |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
     rows |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
  end

  # --- the land ------------------------------------------------------------

  # The far tree line: rounded crowns, lower behind the Taj. Its top at each
  # column.
  defp tree_tops do
    crowns = crowns(-12, 0)

    List.to_tuple(
      for x <- 0..(@w - 1) do
        t0 =
          Enum.reduce(crowns, 64, fn {cx, cy, rad}, t0 ->
            dx = x + 0.5 - cx
            if abs(dx) < rad, do: min(t0, cy - :math.sqrt(rad * rad - dx * dx) * 0.75), else: t0
          end)

        fround(t0 - 0.6 * fbm(x * 0.5, 7, 2, 0))
      end
    )
  end

  defp crowns(x, i) when x < @w + 12 do
    rad = 3 + hash(i, 61) * 4.5
    crown = {x, 60.5 - hash(i, 62) * 2.5 - 2.5 * fbm(x * 0.03, 2, 2, 0) + rad * 0.35, rad}
    [crown | crowns(x + (4 + hash(i, 60) * 5), i + 1)]
  end

  defp crowns(_x, _i), do: []

  defp pool_half(y), do: 0.5 * (y - @hz) + 1
  defp walk_half(y), do: 0.7 * (y - @hz) + 1.5

  # Cypress rows either side of the canal, near ones last: {x, base, height,
  # width, distance}. An inner row along the walks, and a lower outer row
  # further back; the sun is left clear.
  defp trees do
    for s <- [8.5, 10.4, 13, 16.8, 22.5, 31],
        side <- [-1, 1],
        {off, tall} <- [{4.3, 0.8}, {2.45, 1}],
        not (off > 3 and (s > 20 or side > 0)),
        not (side < 0 and s > 30) do
      cxp = @cx + side * off * s

      {cxp + (hash(s * 10, side + off) - 0.5) * 0.6, @hz + s,
       1.6 * tall * s * (0.94 + 0.12 * hash(s * 7, side + 3 + off)), 0.26 * s, s}
    end
  end

  # Long shadows of the cypresses, cast toward us and to the right.
  defp shadow_at(xc, y, trees) do
    Enum.reduce(trees, 1, fn {tx, base, _h, _w, s}, lit ->
      dx = xc - tx
      dy = y - base
      along = (dx * 0.6 + dy * 0.8) / s
      across = (dx * 0.8 - dy * 0.6) / s

      if dy >= -0.5 and along > 0 and along < 3 and abs(across) < 0.17 * (1 - along / 3.4) + 0.03,
        do: lit * (0.08 + 0.92 * smooth(1.6, 3, along)),
        else: lit
    end)
  end

  # The mosque's silhouette, as %{{r, x} => 0 | 1 | 2 | -1}.
  defp mosque_cells do
    for r <- (@mb - 27)..(@mb - 1),
        x <- (@mx - 24)..(@mx + 24),
        into: %{},
        do: {{r, x}, mosque(x + 0.5, r + 0.5)}
  end

  # Every cell as {material, r, g, b, floor, haze, glow}, the floats as the
  # Float32Arrays hold them (the canal's colour is never read).
  defp ground_cells(tops, trees, mq) do
    cells =
      for r <- 0..(@h - 1), x <- 0..(@w - 1), into: %{} do
        {{r, x}, ground_cell(x, r, tops, trees, mq)}
      end

    Enum.reduce(trees, cells, &cypress/2)
  end

  defp ground_cell(x, r, tops, trees, mq) do
    y = r + 0.5
    xc = x + 0.5
    tt = elem(tops, x)

    m =
      cond do
        y < @base and y >= tt -> @bgtree
        y < @base -> @sky
        abs(xc - @cx) < pool_half(y) -> @pool
        abs(xc - @cx) < walk_half(y) -> @walk
        true -> @lawn
      end

    {m, cr, cg, cb, fl, hz, glow} = colour(m, xc, y, tt, trees)

    {m, cr, cg, cb, fl, hz} =
      mosque_colour(Map.get(mq, {r, x}, -1), x, r, mq, {m, cr, cg, cb, fl, hz})

    {m, cr, cg, cb, fl, hz} = marble(x, r, {m, cr, cg, cb, fl, hz})
    {m, cr, cg, cb, fround(fl), fround(hz), glow}
  end

  defp colour(@sky, xc, y, _tt, _trees) do
    {cr, cg, cb} = sky_at(xc, y)
    # Never one flat tone: a faint unevenness in the dawn air.
    veil = 0.88 + 0.24 * fbm(xc * 0.05, y * 0.09, 3, 0)

    {@sky, cr * veil, cg * veil, cb * veil, 0.05 + 0.13 * smooth(18, 42, y),
     0.5 + 0.5 * smooth(20, 58, y), fround(sun_glow(xc, y))}
  end

  # Distant trees, flattened by the haze; rimmed where the sun is close.
  defp colour(@bgtree, xc, y, tt, _trees) do
    tex = fbm(xc * 0.25, y * 0.3, 3, 0)
    depth = smooth(tt, @base, y)
    {sr, sg, sb} = sky_at(xc, tt)
    a = 0.46 - 0.12 * depth + 0.12 * tex
    rim = smooth(tt + 1.8, tt, y) * :math.exp(-abs(xc - @sun_x) / 18)
    cr = mix(0.1, sr, a) + 0.4 * rim
    cg = mix(0.09, sg, a) + 0.27 * rim
    cb = mix(0.15, sb, a) + 0.14 * rim
    # Their feet lost in a bank of ground mist, broken into soft patches.
    patch = 0.45 + 0.75 * smooth(0.3, 0.7, fbm(xc * 0.035 + 11, y * 0.18, 3, 0))
    mist = smooth(tt + 1, @base + 1, y) * 0.75 * min(1, patch)
    mw = :math.exp(-abs(xc - @sun_x) / 90)

    {@bgtree, mix(cr, 0.62 + 0.25 * mw, mist), mix(cg, 0.46 + 0.16 * mw, mist),
     mix(cb, 0.55 + 0.02 * mw, mist), 0.1, 0.8, 0}
  end

  defp colour(@lawn, xc, y, _tt, trees) do
    v = (y - @base) / (@h - @base)
    # Across the ground plane.
    u = (xc - @cx) / (y - @hz)
    tex = fbm(u * 3, 40 / (y - @hz), 3, 0)
    # Mown bands that run toward the Taj.
    stripe = if band(floor(u * 1.4), 1) == 1, do: 1, else: 0.55
    # Low sun raking across the grass from the left: gold where it lands,
    # violet sky-light in the shade.
    lit =
      (0.6 + 0.4 * :math.exp(-abs(xc - @sun_x) / 60)) * stripe * (0.85 + 0.3 * tex) *
        shadow_at(xc, y, trees)

    vig = 1 - 0.45 * smooth(0.5, 1, v) * (0.6 + 0.4 * smooth(40, 0, min(xc, @w - xc)))
    fall = 1 - 0.35 * v
    # Sunlit grass turns from gold near the sun to rose further off.
    warm = :math.exp(-abs(xc - @sun_x) / 80)
    # The shade holds the violet of the sky overhead, brighter in the open.
    amb = 0.75 + 0.5 * stripe - 0.25 * v
    cr = (0.12 * amb + 0.56 * lit * fall) * vig
    cg = (0.09 * amb + (0.36 + 0.14 * warm) * lit * fall) * vig
    cb = (0.24 * amb + (0.26 - 0.1 * warm) * lit * fall) * vig
    # The far lawn sits in the haze.
    far = smooth(@base + 10, @base, y) * 0.7
    mw = :math.exp(-abs(xc - @sun_x) / 90)

    {@lawn, mix(cr, 0.62 + 0.25 * mw, far), mix(cg, 0.46 + 0.16 * mw, far),
     mix(cb, 0.55 + 0.02 * mw, far), 0.1, 0.7 * (1 - v), 0}
  end

  defp colour(@walk, xc, y, _tt, trees) do
    v = (y - @base) / (@h - @base)
    lit = if xc < @cx, do: 1, else: 0.86
    # Paving joints, closer together into the distance.
    joint =
      if(JSMath.mod(90 / (y - @hz), 1) < 0.14, do: 0.72, else: 1) *
        (0.5 + 0.5 * shadow_at(xc, y, trees))

    {@walk, (0.78 - 0.22 * v) * lit * joint, (0.57 - 0.16 * v) * lit * joint,
     (0.53 - 0.12 * v) * lit * joint, 0.15, 0.3, 0}
  end

  defp colour(@pool, _xc, _y, _tt, _trees), do: {@pool, 0, 0, 0, 0.15, 0, 0}

  # The mosque, dark against the sun, its edges caught by it.
  defp mosque_colour(q, _x, _r, _mq, cell) when q < 0, do: cell

  defp mosque_colour(q, x, r, mq, _cell) do
    y = r + 0.5
    xc = x + 0.5
    sg = sun_glow(xc, y)

    {ar, ag, ab} =
      case q do
        1 -> {0.2, 0.11, 0.19}
        2 -> {0.07, 0.04, 0.07}
        0 -> {0.31, 0.13, 0.15}
      end

    # The foot sinks into the mist.
    air = 0.06 + 0.3 * smooth(@mb - 8, @mb, y)
    # Rim light where the cell faces open sky toward the sun.
    lft = if x > 0, do: Map.get(mq, {r, x - 1}, -1), else: -1
    up = if r > 0, do: Map.get(mq, {r - 1, x}, -1), else: -1

    toward =
      cond do
        xc >= @sun_x -> lft
        x < @w - 1 -> Map.get(mq, {r, x + 1}, -1)
        true -> -1
      end

    rim =
      if(up < 0, do: 0.75, else: 0) + if(toward < 0, do: 0.9, else: 0) +
        if(lft < 0 and up < 0, do: 0.2, else: 0)

    rim = min(1, rim) * min(1, 0.25 + sg * 1.6)

    {@mosque, mix(mix(ar, 0.62, air), 1.0, rim * 0.8), mix(mix(ag, 0.44, air), 0.7, rim * 0.8),
     mix(mix(ab, 0.5, air), 0.48, rim * 0.8), 0.04, 0.15}
  end

  # The Taj in front of the sky and the trees: lavender shadow, pink-white
  # front, gold where it faces the sun.
  defp marble(x, r, cell) do
    y = r + 0.5
    xc = x + 0.5

    with true <- y < @base + 0.01,
         {lit, rec} <- taj((xc - @cx) / @s, (@base - y) / @s) do
      {{ar, ag, ab}, {br, bg, bb}, kk} =
        if lit < 0.5,
          do: {{0.42, 0.36, 0.56}, {0.9, 0.76, 0.75}, :math.pow(lit * 2, 1.4)},
          else: {{0.9, 0.76, 0.75}, {1.0, 0.88, 0.72}, (lit - 0.5) * 2}

      {cr, cg, cb} = {mix(ar, br, kk), mix(ag, bg, kk), mix(ab, bb, kk)}

      {cr, cg, cb} =
        if rec > 0 do
          d = 1 - rec * 0.78
          {cr * (d * 0.95), cg * (d * 0.92), cb * d}
        else
          {cr, cg, cb}
        end

      # A little grain in the stone, and the morning haze over the lower
      # storeys.
      g = 0.94 + 0.08 * hash(x * 3 + 1, r * 5 + 2)
      low = smooth(40, @base, y) * 0.2
      {sr, sg, sb} = sky_at(xc, y)
      {@marble, mix(cr * g, sr, low), mix(cg * g, sg, low), mix(cb * g, sb, low), 0.12, 0.55}
    else
      _ -> cell
    end
  end

  # Cypresses, far to near: dark, with a warm rim on the side toward the sun.
  defp cypress({tx, base, h, w, s}, cells) do
    top = base - h
    sun_side = if tx < @cx, do: 0.9, else: 0.6
    # Far trees take more haze.
    dist = smooth(30, 8, s)
    rim_k = 0.5 + 0.5 * :math.exp(-abs(tx - @sun_x) / 80)

    for r <- max(0, floor(top))..(min(@h, ceil(base + 0.6)) - 1)//1,
        y = r + 0.5,
        u = (base - y) / h,
        u <= 1,
        x <- max(0, floor(tx - w - 2))..(min(@w, ceil(tx + w + 2)) - 1)//1,
        reduce: cells do
      cells ->
        xc = x + 0.5

        p =
          cond do
            u < 0.06 -> 0.18
            u < 0.3 -> 0.8 + 0.2 * (u / 0.3)
            true -> :math.pow((1 - u) / 0.7, 0.8)
          end

        n = noise(xc * 0.9, y * 0.55 + s, 0)
        hw = w * p * (0.88 + 0.26 * n) + 0.35
        dx = (xc - tx) / hw

        if abs(dx) > 1 do
          cells
        else
          leaf = fbm(xc * 0.6, y * 0.35 + s * 3, 2, 0)
          rim = smooth(-0.2, -0.9, dx) * (0.4 + 0.6 * leaf) * rim_k
          # Clumps of foliage, each a little lit on top.
          clump = smooth(0.45, 0.7, fbm(xc * 0.45, y * 0.3 + s * 3, 3, 0))
          b = 0.5 + 0.5 * leaf + 0.5 * clump
          cr = mix(0.045 * b + sun_side * rim, 0.7, dist * 0.45)
          cg = mix(0.1 * b + sun_side * 0.63 * rim, 0.5, dist * 0.45)
          cb = mix(0.08 * b + sun_side * 0.27 * rim, 0.56, dist * 0.45)
          hz = (0.3 + 0.4 * dist) * smooth(base - h * 0.7, base, y)
          glow = cells |> Map.fetch!({r, x}) |> elem(6)
          Map.put(cells, {r, x}, {@cypress, cr, cg, cb, fround(0.05), fround(hz), glow})
        end
    end
  end

  # --- init ----------------------------------------------------------------

  @impl true
  def init(_options) do
    trees = trees()
    cells = ground_cells(tree_tops(), trees, mosque_cells())
    {cloud, cloud_lit} = clouds()

    # A gentle shoulder so the brightest light keeps its gradient, and the
    # dot's x ** 1.1 for every step of it (and for the darkest, 1e-4).
    tone =
      List.to_tuple(
        for i <- 0..1024 do
          v = i / 256
          fround(if v < 0.75, do: v, else: 0.75 + 0.25 * (1 - :math.exp(-(v - 0.75) * 4)))
        end
      )

    lift = List.to_tuple(for i <- 0..1024, do: :math.pow(max(elem(tone, i), 1.0e-4), 1.1))

    # The reflection's source: everything above the garden, trees included.
    mirror =
      List.to_tuple(
        for r <- 0..(@base - 1) do
          List.to_tuple(
            for x <- 0..(@w - 1) do
              {m, cr, cg, cb, _fl, _hz, _glow} = cells[{r, x}]
              {m == @marble, fround(cr), fround(cg), fround(cb)}
            end
          )
        end
      )

    %{
      cells:
        List.to_tuple(
          for r <- 0..(@h - 1) do
            List.to_tuple(for x <- 0..(@w - 1), do: cell(x, r, cells[{r, x}]))
          end
        ),
      clouds: {cloud, cloud_lit},
      hazes: hazes(),
      mirror: mirror,
      tone: tone,
      lift: lift,
      birds:
        for(
          i <- 0..2,
          do: {58 + i * 8 + hash(i, 40) * 4, 30 - i * 2.5 + hash(i, 41) * 2, hash(i, 42) * 6.28}
        ),
      lut: Palette.nearest_lut(@meta.palette)
    }
  end

  # Drifting haze, two layers in a strip that wraps, and how thick it is on
  # each row: thickest just above the garden.
  defp hazes do
    List.to_tuple(
      for r <- 0..(@h - 1) do
        h1 =
          for x <- 0..(@hwd - 1),
              do: fround(smooth(0.4, 0.75, fbm(x * 0.018, r * 0.09, 4, @hwd * 0.018)))

        h2 =
          for x <- 0..(@hwd - 1),
              do: fround(smooth(0.42, 0.8, fbm(x * 0.04 + 7, r * 0.16 + 3, 3, @hwd * 0.04)))

        {fround(0.03 + 0.42 * :math.exp(-abs(r + 0.5 - 63) / 6)), List.to_tuple(h1),
         List.to_tuple(h2)}
      end
    )
  end

  # What a cell keeps for the frame: its kind and what that needs, then its
  # ordered dither, nudged per cell so the grid does not show in flat light.
  defp cell(x, r, {m, cr, cg, cb, fl, hz, glow}) do
    k = r * @w + x
    dither = {fround(elem(@bayer, band(r, 3) * 4 + band(x, 3)) * 0.85), fround(hash(k, 77) - 0.5)}
    {kind(m, x, r, {fround(cr), fround(cg), fround(cb), fl, hz, glow}), dither}
  end

  defp kind(@pool, x, r, _cell) do
    y = r + 0.5
    depth = (y - @base) / (@h - @base)

    line =
      if r > @base and r <= @base + 4,
        do: {x * 0.55, r * 2.7, 0.5 - 0.08 * (r - @base)}

    {:pool, {y * 1.9, x * 0.11, 0.2 + 0.7 * depth}, {x * 0.3, @base - 0.5 - (y - @base) * @kr},
     0.1 * depth, {x * 0.12, y * 0.9}, line, r == @base, 0.8 + 0.2 * smooth(@h + 2, @h - 6, y)}
  end

  defp kind(@sky, x, r, {cr, cg, cb, fl, hz, glow}) do
    y = r + 0.5
    # The last few stars, fading where the dawn reaches.
    star =
      if r < 24 and x > 96 and hash(x, r * 3 + 11) > 0.988,
        do: {1.2 + hash(x, r) * 2, hash(r, x) * 6.28, smooth(24, 8, r), smooth(96, 140, x)}

    # The sun's disc, softened by the haze.
    dx = x + 0.5 - @sun_x
    dy = y - @sun_y
    dd = dx * dx + dy * dy
    disc = if dd < 22, do: smooth(22, 9, dd)

    {:sky, cr, cg, cb, fl, hz, glow, star, disc}
  end

  defp kind(_m, _x, _r, {cr, cg, cb, fl, hz, _glow}), do: {:solid, cr, cg, cb, fl, hz}

  # --- the frame -----------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    breathe = 0.035 * :math.sin(t / 6 * :math.pi() * 2)

    fr = %{
      t: t,
      d1: t * 1.1,
      d2: t * 2.3,
      cd: t * 0.5,
      breathe: breathe,
      birds: birds(state.birds, t),
      pool: {t * 2.4, t * 0.7, t * 1.3, t * 0.15, t * 0.9, t * 0.2},
      color?: env.color?
    }

    {lines, lut} =
      Enum.map_reduce(0..(@h - 1), state.lut, fn r, lut ->
        # The birds on this row.
        fr = %{fr | birds: for({^r, x} <- fr.birds, do: x)}
        line(0, r, elem(state.cells, r), elem(state.hazes, r), state, fr, lut, <<>>, <<>>)
      end)

    text = lines |> Enum.map(&elem(&1, 0)) |> Enum.intersperse(?\n)
    colors = if env.color?, do: IO.iodata_to_binary(Enum.map(lines, &elem(&1, 1)))
    {text, colors, %{state | lut: lut}}
  end

  # Where the birds are this frame, as the {row, column} of each cell they
  # darken.
  defp birds(birds, t) do
    for {x0, y0, ph} <- birds,
        bx = JSMath.round(JSMath.mod(JSMath.mod(x0 + t * 3.2, 260) + 260, 260) - 30),
        by = JSMath.round(y0 + :math.sin(t * 0.4 + ph) * 1.3),
        {ox, oy} <-
          if(:math.sin(t * 7 + ph) > 0,
            do: [{0, 0}, {1, 1}, {-1, 1}, {2, 1}, {-2, 1}],
            else: [{0, 0}, {1, 0}, {-1, 0}, {2, -1}, {-2, -1}]
          ),
        do: {by - oy, bx - ox}
  end

  defp line(@w, _r, _cells, _hazes, _state, _fr, lut, chars, colors),
    do: {{chars, colors}, lut}

  defp line(x, r, cells, hazes, state, fr, lut, chars, colors) do
    {kind, dither} = elem(cells, x)
    {cr, cg, cb, fl, fade, hw, sky?} = shade(kind, x, r, state, fr)
    {cr, cg, cb} = haze(hw, x, hazes, fr, cr, cg, cb)
    {ch, i, lut} = dot(cr, cg, cb, {fl, fade, dither, sky?}, state, fr.color?, lut)

    line(
      x + 1,
      r,
      cells,
      hazes,
      state,
      fr,
      lut,
      <<chars::binary, ch::binary>>,
      <<colors::binary, i>>
    )
  end

  # The morning haze, drifting: `hw` is how much of it the cell takes.
  defp haze(hw, _x, _hazes, _fr, cr, cg, cb) when hw == 0, do: {cr, cg, cb}

  defp haze(hw, x, {hr, h1, h2}, fr, cr, cg, cb) do
    a = hw * hr
    i1 = trunc(:math.fmod(x + fr.d1, @hwd))
    i2 = trunc(:math.fmod(x + fr.d2, @hwd))
    hz = a * (0.35 + 0.75 * elem(h1, i1) + 0.45 * elem(h2, i2))
    {mix(cr, 0.9, hz), mix(cg, 0.64, hz), mix(cb, 0.62, hz)}
  end

  # Tone mapped, then dot size from brightness, dithered; the colour
  # brightened or dimmed to make up for the dot's size.
  defp dot(cr, cg, cb, {fl, fade, {dith, jit}, sky?}, state, color?, lut) do
    ir = min(1024, trunc(cr * 256))
    ig = min(1024, trunc(cg * 256))
    ib = min(1024, trunc(cb * 256))
    tone = state.tone
    top = ir |> max(ig) |> max(ib)
    peak = if top == 0, do: 1.0e-4, else: elem(tone, top)
    level = clamp(fl + (1 - fl) * elem(state.lift, top) * 1.02) * fade
    d = level * 3 + dith + jit * if(level < 0.3, do: 0.12, else: 0.3)
    step = max(0, min(3, round_js(d)))

    if color? do
      want = if step != 0, do: min(1, (level + 0.06) / elem(@cover, step)), else: 0
      s = (0.3 + 0.7 * want) / peak
      s = if sky? and s > 1.6, do: 1.6, else: s
      tr = clamp(elem(tone, ir) * s)
      tg = clamp(elem(tone, ig) * s)
      tb = clamp(elem(tone, ib) * s)
      {i, lut} = lookup(lut, tr, tg, tb)
      {elem(@dots, step), i, lut}
    else
      {elem(@dots, step), 0, lut}
    end
  end

  defp lookup({_palette, answers} = lut, tr, tg, tb) do
    key = bsl(cube(tr), 10) ||| bsl(cube(tg), 5) ||| cube(tb)

    case answers do
      %{^key => i} -> {i, lut}
      _ -> Palette.nearest(lut, tr, tg, tb)
    end
  end

  defp cube(v), do: min(31, trunc(v * 31.99))

  # --- each kind in a frame --------------------------------------------------

  defp shade({:solid, cr, cg, cb, fl, hw}, _x, _r, _state, _fr),
    do: {cr, cg, cb, fl, 1, hw, false}

  defp shade({:pool, wobble, row, dim, ripple, line, edge?, fade}, x, r, state, fr) do
    # The mirror: the scene above, flipped about the far end, shortened and
    # shaken.
    {y19, x011, wob_k} = wobble
    {x03, sr0} = row
    {t24, t07, t13, t015, t09, t02} = fr.pool
    y = r + 0.5
    wob = :math.sin(y19 - t24 + :math.sin(x011 + t07) * 1.5) * wob_k
    sx = JSMath.round(x + wob) |> max(0) |> min(@w - 1)
    sr = sr0 - if(:math.sin(x03 + t13 + y) > 0.6, do: 1, else: 0)
    sr = JSMath.round(sr) |> max(0) |> min(@base - 1)
    {marble?, mr, mg, mb} = state.mirror |> elem(sr) |> elem(sx)
    # Stone reflects brighter than the sky does, so the Taj holds its shape.
    dim = if(marble?, do: 1.0, else: 0.85) - dim
    cr = mr * dim * 0.9
    cg = mg * dim * 0.94
    cb = mb * dim + 0.05
    # Ripples catching the sky.
    {x012, y09} = ripple
    glint = smooth(0.75, 0.95, noise(x012 + t015, y09 - t09, 0)) * 0.14
    {cr, cg, cb} = {cr + glint, cg + glint * 0.85, cb + glint * 0.75}

    # A sparse line of light drifting across the far end.
    {cr, cg, cb} =
      case line do
        {x055, r27, k} ->
          gl = smooth(0.62, 0.85, noise(x055 - t09, r27 + t02, 0)) * k
          {cr + gl, cg + gl * 0.85, cb + gl * 0.6}

        nil ->
          {cr, cg, cb}
      end

    # A thin line of light where the far edge meets the plinth.
    {cr, cg, cb} = if edge?, do: {cr + 0.2, cg + 0.16, cb + 0.12}, else: {cr, cg, cb}
    {cr, cg, cb, fround(0.15), fade, 0.12, false}
  end

  defp shade({:sky, cr, cg, cb, fl, hw, glow, star, disc}, x, r, state, fr) do
    ga = glow * fr.breathe
    {cr, cg, cb} = {cr + ga, cg + ga * 0.78, cb + ga * 0.48}

    {cr, cg, cb} =
      if r < @ch, do: cloud(state.clouds, x, r, glow, fr.cd, cr, cg, cb), else: {cr, cg, cb}

    {cr, cg, cb} = star(star, fr.t, cr, cg, cb)

    {cr, cg, cb} =
      if disc != nil,
        do: {mix(cr, 1.05, disc), mix(cg, 0.98, disc), mix(cb, 0.86, disc)},
        else: {cr, cg, cb}

    # Birds, dark against the light.
    if x in fr.birds,
      do: {0.16, 0.1, 0.17, 0, 1, hw, true},
      else: {cr, cg, cb, fl, 1, hw, true}
  end

  # Drifting dawn cloud: gold and rose underneath near the sun, violet-grey
  # elsewhere.
  defp cloud({cloud, cloud_lit}, x, r, glow, cd, cr, cg, cb) do
    sx = x + cd
    ix = floor(sx)
    fx = sx - ix
    i0 = rem(ix, @cw)
    i1 = rem(ix + 1, @cw)
    row = elem(cloud, r)
    c0 = elem(row, i0)
    c = c0 + (elem(row, i1) - c0) * fx

    if c > 0.01 do
      row = elem(cloud_lit, r)
      l0 = elem(row, i0)
      l = l0 + (elem(row, i1) - l0) * fx
      near = min(1, glow * 1.7)
      # A mauve body, rose underneath, gold where the sun is close.
      b2 = clamp(0.2 + 0.6 * l + near * 0.55 * l)

      {kr, kg, kb} =
        if b2 < 0.5 do
          q = b2 * 2
          {mix(0.16, 0.6, q), mix(0.12, 0.34, q), mix(0.3, 0.5, q)}
        else
          q = (b2 - 0.5) * 2
          {mix(0.6, 1.05, q), mix(0.34, 0.8, q), mix(0.5, 0.55, q)}
        end

      a = min(1, c) * 0.9
      {mix(cr, kr, a), mix(cg, kg, a), mix(cb, kb, a)}
    else
      {cr, cg, cb}
    end
  end

  defp star(nil, _t, cr, cg, cb), do: {cr, cg, cb}

  defp star({speed, phase, fade_r, fade_x}, t, cr, cg, cb) do
    tw = 0.7 + 0.3 * :math.sin(t * speed + phase)
    s = tw * 0.62 * fade_r * fade_x
    {max(cr, s * 0.85), max(cg, s * 0.85), max(cb, s)}
  end
end
