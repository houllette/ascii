defmodule AsciiArt.Pieces.Saptarishi do
  @moduledoc """
  The big dipper at true positions in a twinkling sky.

  The seven stars of the Big Dipper where they really sit, with Alcor beside
  Mizar, in a strip of twinkling sky crossed now and then by a meteor.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `lines` - the dipper's shape, drawn in dotted lines from star to star.
      Default `true`; `false` leaves the stars on their own.

  The picture is always 64 by 18.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `AsciiArt.Ink`),
  or on a page a CSS variable. It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "saptarishi: the big dipper
  at true positions in a twinkling sky". A player's or a component's `label`
  gives words of your own, as "the Big Dipper".

  ## Example

  ```elixir
  draw = fn lines -> "saptarishi" |> AsciiArt.new!(options: %{lines: lines}) |> AsciiArt.frame(0.0) |> elem(0) end
  draw.(true).text == draw.(false).text
  #=> false
  ```

  ```heex
  <AsciiArt.Phoenix.player socket={@socket} id="sky" piece="saptarishi" options={%{lines: false}} ink="#cfd8dc" />
  ```

  Ported from `src/pieces/saptarishi.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Hash

  @meta %AsciiArt.Meta{
    name: "saptarishi",
    category: :space,
    note: "the big dipper at true positions in a twinkling sky",
    cols: 64,
    rows: 18,
    fps: 12,
    options: %{lines: true}
  }

  # Right ascension in hours, declination in degrees. Megrez is the dim one,
  # and only the seven ever wear a * or a +.
  @seven [
    # Dubhe
    {11.062, 61.751, "*"},
    # Merak
    {11.031, 56.383, "*"},
    # Phecda
    {11.897, 53.695, "*"},
    # Megrez
    {12.257, 57.033, "+"},
    # Alioth
    {12.901, 55.96, "*"},
    # Mizar
    {13.399, 54.925, "*"},
    # Alkaid
    {13.792, 49.313, "*"}
  ]
  @edges [{6, 5}, {5, 4}, {4, 3}, {3, 0}, {0, 1}, {1, 2}, {2, 3}]
  # Seconds between meteors, give or take.
  @meteor 11

  @impl true
  def meta, do: @meta

  defp hash(x, y), do: Hash.murmur(x, y)
  defp ease(t), do: t * t * (3 - 2 * t)
  defp clamp(x), do: min(1, max(0, x))

  # A dot sits high, mid or low in its cell, so a slope can pass through.
  defp dot(sub) when sub < 0.36, do: "'"
  defp dot(sub) when sub < 0.64, do: "·"
  defp dot(_sub), do: "."

  @impl true
  def init(%{lines: lines}) do
    %{cols: cols, rows: rows} = @meta

    # Facing north, east on the left: a tangent-plane projection in cells,
    # where a row is two columns tall.
    rad = :math.pi() / 180
    a0 = 186 * rad
    d0 = 55.5 * rad

    plane =
      for {ra, dec, _} <- @seven do
        a = ra * 15 * rad - a0
        d = dec * rad

        k =
          :math.sin(d0) * :math.sin(d) + :math.cos(d0) * :math.cos(d) * :math.cos(a)

        {-:math.cos(d) * :math.sin(a) / k,
         (:math.sin(d0) * :math.cos(d) * :math.cos(a) - :math.cos(d0) * :math.sin(d)) / k}
      end

    {xlo, xhi} = plane |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {ylo, yhi} = plane |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    s = (cols - 12) / (xhi - xlo)

    # The seven, and Alcor a cell up and to the east of Mizar, clear of both
    # of Mizar's lines.
    cell =
      for {x, y} <- plane do
        {JSMath.round(cols / 2 - 0.5 + s * (x - (xhi + xlo) / 2)),
         JSMath.round(rows / 2 - 0.5 + s / 2 * (y - (yhi + ylo) / 2))}
      end

    sky =
      cell
      |> Enum.zip(@seven)
      |> Enum.reduce(%{}, fn {{c, r}, {_, _, ch}}, sky -> Map.put(sky, r * cols + c, ch) end)

    used = Enum.reduce(cell, MapSet.new(), fn {c, r}, used -> keep(used, c, r, 3, 1) end)
    {mc, mr} = Enum.at(cell, 5)
    sky = Map.put(sky, (mr - 1) * cols + mc - 1, ".")
    cell = List.to_tuple(cell)

    {sky, used} =
      Enum.reduce(@edges, {sky, used}, fn {i, j}, acc ->
        stroke(elem(cell, i), elem(cell, j), lines, acc)
      end)

    # Field stars: sparse, never touching, thinning toward the ends. Most are
    # a faint . and a few a ·, and each now and then dims out for a moment.
    {field, _} =
      for r <- 0..(rows - 1), c <- 0..(cols - 1), reduce: {[], used} do
        {field, used} ->
          if MapSet.member?(used, r * cols + c) or
               hash(c, r) >= 0.058 * ease(clamp(min(c, cols - 1 - c) / 9)) do
            {field, used}
          else
            star =
              {r * cols + c, if(hash(r, c + 99) > 0.85, do: "·", else: "."),
               0.35 + 0.7 * hash(c, r + 7)}

            {[star | field], keep(used, c, r, 2, 1)}
          end
      end

    %{sky: sky, field: field |> Enum.reverse() |> Enum.with_index()}
  end

  defp keep(used, c, r, mc, mr) do
    %{cols: cols, rows: rows} = @meta

    for j <- -mr..mr,
        i <- -mc..mc,
        r + j >= 0 and r + j < rows and c + i >= 0 and c + i < cols,
        reduce: used,
        do: (used -> MapSet.put(used, (r + j) * cols + c + i))
  end

  # Each line is a sparse dotted stroke from star cell to star cell: a dot
  # about every two columns, each taken from the point nearest its cell's
  # centre, stopping short of the stars at either end.
  defp stroke({x0, y0} = a, {x1, y1} = b, lines, {sky, used}) do
    cols = @meta.cols
    n = JSMath.ceil(JSMath.hypot(x1 - x0, 2 * (y1 - y0)) * 8)

    {run, used} =
      Enum.reduce(0..n, {[], used}, fn q, {run, used} ->
        x = x0 + (x1 - x0) * q / n
        y = y0 + (y1 - y0) * q / n
        c = JSMath.round(x)
        r = JSMath.round(y)
        sub = y - r + 0.5
        used = keep(used, c, r, 1, 1)
        dx = x - c
        dy = 2 * (sub - 0.5)
        off = dx * dx + dy * dy

        case run do
          [{^c, ^r, last_off, _} | rest] when off < last_off -> {[{c, r, off, sub} | rest], used}
          [{^c, ^r, _, _} | _] -> {run, used}
          _ -> {[{c, r, off, sub} | run], used}
        end
      end)

    {sky, _, _} =
      run
      |> Enum.reverse()
      |> Enum.reduce({sky, -9, -9}, fn {c, r, _, sub}, {sky, lc, ly} ->
        if not lines or not clear?(c, r, a, b) or JSMath.hypot(c - lc, 2 * (r + sub - ly)) < 1.8 do
          {sky, lc, ly}
        else
          {Map.put_new(sky, r * cols + c, dot(sub)), c, r + sub}
        end
      end)

    {sky, used}
  end

  defp clear?(c, r, a, b) do
    Enum.all?([a, b], fn {sc, sr} ->
      abs(sr - r) > 1 or abs(sc - c) > if(sr == r, do: 2, else: 1)
    end)
  end

  @impl true
  def frame(%{sky: sky, field: field} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta

    out =
      Enum.reduce(field, sky, fn {{k, ch, rate}, i}, out ->
        x = t * rate
        n = JSMath.floor(x)
        e = ease(x - n)
        h = hash(n, i + 7)
        w = h + (hash(n + 1, i + 7) - h) * e
        Map.put(out, k, if(w < 0.2, do: " ", else: ch))
      end)

    # A meteor every so often: a head with a tail that thins out behind it.
    m0 = max(0, JSMath.floor((t - 2 + 2.5) / @meteor))
    out = Enum.reduce([m0 - 1, m0], out, &meteor(&2, &1, t, sky))

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(out, r * cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp meteor(out, m, _t, _sky) when m < 0, do: out

  defp meteor(out, m, t, sky) do
    start = 2 + m * @meteor + if(m != 0, do: hash(m, 3) * 4 - 2, else: 0)
    age = (t - start) / 0.8

    if age <= 0 or age >= 1.45, do: out, else: streak(out, m, age, sky)
  end

  defp streak(out, m, age, sky) do
    %{cols: cols, rows: rows} = @meta
    dir = if hash(m, 5) < 0.5, do: 1, else: -1
    len = 18 + 8 * hash(m, 6)
    drop = 3 + 3 * hash(m, 7)

    x0 =
      if dir > 0,
        do: 4 + hash(m, 8) * (cols - len - 8),
        else: cols - 5 - hash(m, 8) * (cols - len - 8)

    y0 = 0.6 + hash(m, 9) * (rows - drop - 2.2)
    front = min(age, 1)
    back = max(0, age - 0.45)

    open? = fn c, r ->
      c >= 0 and c < cols and r >= 0 and r < rows and not star?(sky, r * cols + c)
    end

    out =
      JSMath.ceil(back * 40)
      |> Stream.iterate(&(&1 + 1))
      |> Enum.take_while(&(&1 <= front * 40))
      |> Enum.reduce(out, fn q, out ->
        f = q / 40
        x = x0 + dir * len * f
        y = y0 + drop * f
        c = JSMath.round(x)
        r = JSMath.floor(y)
        sub = y - r

        if open?.(c, r) do
          fresh = (f - back) / max(1.0e-6, front - back)
          Map.put(out, r * cols + c, tail(fresh, sub))
        else
          out
        end
      end)

    if age < 1 do
      c = JSMath.round(x0 + dir * len * age)
      r = JSMath.floor(y0 + drop * age)
      if open?.(c, r), do: Map.put(out, r * cols + c, "o"), else: out
    else
      out
    end
  end

  defp star?(sky, k), do: Map.get(sky, k, " ") in ["*", "+"]

  defp tail(fresh, sub) when fresh > 0.5 do
    cond do
      sub < 0.34 -> "'"
      sub < 0.67 -> "-"
      true -> "_"
    end
  end

  defp tail(_fresh, sub), do: if(sub < 0.5, do: "·", else: ".")
end
