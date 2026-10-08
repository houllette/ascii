defmodule AsciiArt.Pieces.Earth do
  @moduledoc """
  A lit globe turning, continents from a five-degree map.

  The globe turning west to east under a sun low on its left, its continents
  read off a hand-made map of the world at five degrees a cell.

  Ported from `src/pieces/earth.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Rand

  @meta %AsciiArt.Meta{
    name: "earth",
    category: :space,
    note: "a lit globe turning, continents from a five-degree map",
    cols: 60,
    rows: 30,
    fps: 20,
    loop: 36
  }

  # Equirectangular, 180 W at the left, the north pole at the top; # is land.
  @map [
    "                                                                        ",
    "                     ##   ######                                        ",
    "             ###################       #                #               ",
    "           ###########   #######                  ###########           ",
    "#  ##############   ###  #####         #################################",
    "   ##############    ##   ##    #    ### ############################## ",
    "    #    #########  ####           # ## ########################   ##   ",
    "          ###############         ## ###########################        ",
    "           #############           #############################        ",
    "           ###########            ### ####  ## ###############  #       ",
    "           ##########             ##     ################### #          ",
    "            ########              ##### #  #################  #         ",
    "             ####  #             ###########################            ",
    "               ##                ###############  #########             ",
    "                ###              ##############    ##  ###  #           ",
    "                  ##             #############     #    ##  #           ",
    "                    #####         ############          #   #           ",
    "                    ######            #######          ## ##            ",
    "                    ########          ######            # ### ##        ",
    "                    #########         ######             ##    ###      ",
    "                     ########          #####                  #         ",
    "                      ######          ###### #               ####       ",
    "                      ######           ####  #             #######      ",
    "                      ####             ####                ########     ",
    "                     ####              ###                 #######      ",
    "                     ###                                        ##      ",
    "                     ##                                               # ",
    "                     ##                                                 ",
    "                     #                                                  ",
    "                                                                        ",
    "                                                                        ",
    "                       #                       ##################       ",
    "                    ####        ######################################  ",
    "  ####################################################################  ",
    "########################################################################",
    "########################################################################"
  ]
  @mw 72
  @mh 36

  # Land and sea keep apart at every light: land is the dense family and goes
  # on into the dusk, sea is a light texture that fades into the night first.
  @land {":", "+", "*", "#", "%", "@"}
  # On paper land stays heavy, darkest at the dusk.
  @paper_land {"#", "#", "%", "%", "%", "@"}
  # Seconds per turn.
  @day 36
  # Longitude facing us at t = 0, degrees east.
  @start 20
  # The north pole leans this far toward us, radians.
  @tilt 0.3
  # Samples per cell each way.
  @ss 2

  @compile {:inline, at: 3}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    cx = cols / 2
    cy = rows / 2
    # Radius in rows; it spans twice as many columns.
    rr = rows / 2 - 1

    land =
      @map
      |> Enum.map(fn line ->
        line
        |> String.to_charlist()
        |> Enum.map(&if(&1 == ?#, do: 1.0, else: 0.0))
        |> List.to_tuple()
      end)
      |> List.to_tuple()

    # Each sample keeps where it falls on the globe, how much sun it gets and
    # how much of the sun the sea there would mirror back at us. The sun is
    # behind us and a little left and above, so the whole disc is lit but for
    # a thin crescent of night on the right.
    m = JSMath.hypot(-0.42, 0.28, 0.86)
    light = {-0.42 / m, 0.28 / m, 0.86 / m}
    {lx, ly, lz} = light
    hm = JSMath.hypot(lx, ly, lz + 1)
    half = {lx / hm, ly / hm, (lz + 1) / hm}
    tilt = {:math.cos(@tilt), :math.sin(@tilt)}

    samples =
      for r <- 0..(rows - 1), c <- 0..(cols - 1) do
        for j <- 0..(@ss - 1),
            i <- 0..(@ss - 1),
            x = (c + (i + 0.5) / @ss - cx) / (2 * rr),
            y = (cy - r - (j + 0.5) / @ss) / rr,
            x * x + y * y < 1,
            do: sample(x, y, light, half, tilt)
      end
      |> List.to_tuple()

    inside = fn c, r ->
      c >= 0 and c < cols and r >= 0 and r < rows and
        length(elem(samples, r * cols + c)) * 4 * 2 >= 4 * @ss * @ss
    end

    # A few faint stars, kept clear of the globe.
    {stars, _} =
      Enum.map_reduce(0..(rows * cols - 1), Rand.seed(5), fn k, rand ->
        r = div(k, cols)
        c = rem(k, cols)

        if JSMath.hypot((c + 0.5 - cx) / (2 * rr), (cy - r - 0.5) / rr) > 1.1 do
          {x, rand} = Rand.next(rand)
          {x < 0.03, rand}
        else
          {false, rand}
        end
      end)

    stars = List.to_tuple(stars)

    cells =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          if inside.(c, r) do
            # The limb: every globe cell with open space on any side, corners
            # included, so the edge of the night side is one unbroken ring.
            rim = Enum.any?(for dr <- -1..1, dc <- -1..1, do: not inside.(c + dc, r + dr))
            globe(elem(samples, r * cols + c), rim)
          else
            if elem(stars, r * cols + c), do: ".", else: " "
          end
        end
      end

    %{land: land, cells: cells}
  end

  defp sample(x, y, {lx, ly, lz}, {hx, hy, hz}, {ct, st}) do
    z = :math.sqrt(1 - (x * x + y * y))
    py = y * ct + z * st
    pz = z * ct - y * st
    lat = :math.asin(py)
    lon = :math.atan2(x, pz)
    sun = max(0, x * lx + y * ly + z * lz)
    glint = :math.pow(max(0, x * hx + y * hy + z * hz), 300)
    {lon, (:math.pi() / 2 - lat) / :math.pi() * @mh, sun, glint}
  end

  # What never changes in a globe cell: where its samples fall, its mean light
  # and glint, and whether it is on the limb.
  defp globe([{_, v0, _, _} | _] = s, rim) do
    k = length(s)
    v = Enum.reduce(s, 0, fn {_, _, sun, _}, v -> v + sun end) / k
    g = Enum.reduce(s, 0, fn {_, _, _, glint}, g -> g + glint end) / k
    {for({lon, lat, _, _} <- s, do: {lon, lat}), k, v, g, rim, v0}
  end

  # How much land is at a point of the map, blended between cells.
  defp at(land, u, v) do
    x = u - 0.5
    y = min(@mh - 1, max(0, v - 0.5))
    x0 = JSMath.floor(x)
    y0 = JSMath.floor(y)
    fx = x - x0
    fy = y - y0
    y1 = min(@mh - 1, y0 + 1)
    a = rem(rem(x0, @mw) + @mw, @mw)
    b = rem(a + 1, @mw)
    row0 = elem(land, y0)
    row1 = elem(land, y1)
    top = elem(row0, a) * (1 - fx) + elem(row0, b) * fx
    bot = elem(row1, a) * (1 - fx) + elem(row1, b) * fx
    top * (1 - fy) + bot * fy
  end

  # A fixed scatter of wave crests on the sea, so the texture turns with the globe.
  defp crest?(u, v) do
    h =
      :math.sin(JSMath.floor(u * 1.5) * 12.9898 + JSMath.floor(v * 1.5) * 78.233) * 43_758.5453

    h - JSMath.floor(h) < 0.12
  end

  @impl true
  def frame(%{land: land, cells: cells} = state, t, env) do
    turn = (@start - 360 * JSMath.mod(t, @day) / @day) * :math.pi() / 180

    lines =
      for row <- cells do
        for cell <- row, do: cell(cell, land, turn, env.paper)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(ch, _land, _turn, _paper) when is_binary(ch), do: ch

  defp cell({s, k, v, g, rim, v0}, land, turn, paper) do
    {l, u0} =
      Enum.reduce(s, {0, nil}, fn {lon, lat}, {l, u0} ->
        u = JSMath.mod(((lon + turn) / (2 * :math.pi()) + 0.5) * @mw, @mw)
        u = if u < 0, do: u + @mw, else: u
        {l + at(land, u, lat), u0 || u}
      end)

    shade(l / k, v, g, rim, paper, u0, v0)
  end

  defp shade(l, v, _g, rim, _paper, _u0, _v0) when l >= 0.5 and v < 0.03,
    do: if(rim, do: ".", else: "·")

  # Land shows down to a sliver of light, past where the sea goes dark, and
  # stays faintly there through the night so the globe reads whole.
  defp shade(l, v, _g, _rim, paper, _u0, _v0) when l >= 0.5 do
    i = min(tuple_size(@land) - 1, JSMath.floor(if(paper, do: 1 - v, else: v) * 1.15 * 6))
    elem(if(paper, do: @paper_land, else: @land), i)
  end

  defp shade(_l, v, _g, rim, _paper, _u0, _v0) when v < 0.1, do: if(rim, do: ".", else: " ")
  # The sea: dots, dashes in fuller light, a few crests, and the sun's glint.
  defp shade(_l, _v, g, _rim, _paper, _u0, _v0) when g > 0.4, do: "="

  defp shade(_l, v, g, _rim, _paper, u0, v0) when v > 0.5 do
    if g > 0.08 or crest?(u0, v0), do: "~", else: "-"
  end

  defp shade(_l, _v, _g, _rim, _paper, _u0, _v0), do: "."
end
