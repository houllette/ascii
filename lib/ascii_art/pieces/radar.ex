defmodule AsciiArt.Pieces.Radar do
  @moduledoc """
  Rotating sweep with afterglow, contacts fade between passes.

  A round scope with range rings and a sweep turning clockwise. Its
  afterglow trails behind; contacts light as the beam crosses them, then
  fade. As upstream draws it, contacts cross on made-up tracks over a
  coast; give it `contacts` and it shows yours.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`), as your
  contacts move: the scope is drawn anew from them, the beam where play
  time puts it.

    * `contacts` - each a map of its `bearing`, in degrees clockwise from
      north, its `range`, in the scope's units, and optionally its `size`,
      1 or 2 cells wide. They light as the beam crosses them and fade until
      it comes round again, as upstream's do, over the land too; one beyond
      the scope's range, or without a bearing or range, is not shown, and
      one at its very edge is drawn just inside the bezel. Default `[]`:
      contacts cross the scope on upstream's tracks.
    * `range` - the scope's reach, in the top corner; its rings are a third
      of it apart, in the bottom one. Default 24.
    * `unit` - the range's unit. Default `"nm"`.
    * `land` - `false` leaves out the coast that lies to the south-west.
      Default `true`.

  The frame is always 53 by 25.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `AsciiArt.Ink`); part by part with `:parts` (see `AsciiArt.Parts`),
  `parts: true` taking the colours suggested here:

    * `bezel` - the rim, grey.
    * `ring` - the range rings' dots and the centre's `+`, grey.
    * `scale` - the bearings at the rim, grey.
    * `land` - the coast's land, orange; `land.coast`, its edge, which
      flares as the beam passes, as the land's unless given its own.
    * `sweep` - the beam's afterglow, green; `sweep.beam`, the beam itself,
      as the sweep's unless given its own.
    * `contact` - the contacts, green.
    * `readout` - the texts in the corners.

  Each frame's parts are drawn again from its time, so they are exact.

  ## Keys and clicks

  It takes none: it shows contacts, and `AsciiArt.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still tells
  your LiveView where it was clicked, and on which part
  (`AsciiArt.part_at/4`): a `contact`, say.

  ## Screen readers

  `AsciiArt.describe/1` reads the contacts given and the scope's range:
  "radar: 2 contacts within 24 nm". Playing upstream's tracks, it gives the
  piece's name and note.

  ## Example

  ```elixir
  contacts = [%{bearing: 40, range: 9}, %{bearing: 130, range: 18, size: 2}]
  scope = AsciiArt.new!("radar", options: %{contacts: contacts, land: false}, parts: true)

  AsciiArt.describe(scope)
  #=> "radar: 2 contacts within 24 nm"

  {frame, _scope} = AsciiArt.frame(scope, 2.0)
  frame.text =~ "contacts 2"
  #=> true
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="scope" piece="radar" options={%{contacts: @contacts, land: false}} parts />
  ```

  Ported from `src/pieces/radar.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{JSMath, Parts}
  alias AsciiArt.Kit.Text
  import Bitwise, only: [>>>: 2, <<<: 2, |||: 2]

  @meta %AsciiArt.Meta{
    name: "radar",
    category: :data,
    note: "rotating sweep with afterglow, contacts fade between passes",
    cols: 53,
    rows: 25,
    fps: 30,
    options: %{range: 24, unit: "nm", contacts: [], land: true},
    bounds: %{contacts: %{range: {0, 1.0e9}, size: {1, 2}}},
    shapes: %{contacts: [%{bearing: 0.0, range: 0.0, size: 1}]},
    parts: [
      {"bezel", "#8b949e"},
      {"ring", "#8b949e"},
      {"scale", "#8b949e"},
      {"land", "#db6d28"},
      {"land.coast", nil},
      {"sweep", "#3fb950"},
      {"sweep.beam", nil},
      {"contact", "#3fb950"},
      {"readout", nil}
    ]
  }

  # Scope radius in pixels; a pixel is a cell wide and half a cell tall.
  @r 19
  # Seconds per revolution; radians of afterglow behind the beam; seconds for
  # a return to fade to a third.
  @turn 4
  @trail 0.8
  @fade 2.4
  @half {" ", "▀", "▄", "█"}
  @shade {" ", "░", "▒", "▓", "█"}
  # The centre in pixels: a column, and between two pixel rows.
  @cx 26
  @cy 24.5
  # The mirror row, 2 * @cy, a whole number of pixels.
  @cy2 trunc(2 * @cy)

  # Contacts on straight tracks across the scope; each leaves, stays out for a
  # few pixels of travel, and comes back in on the far side. Heading, offset
  # from the centre, speed in pixels a second, start along the track, size, gap.
  @tracks [
    {1.05, -5, 1.1, 15, 2, 8},
    {3.45, 6, 0.9, -1, 2, 10},
    {5.3, 9, 1.2, 4, 1, 6},
    {2.1, -11, 0.8, -9, 1, 8},
    {0.4, 3, 1.3, -21, 1, 8},
    {4.75, 13, 0.7, 2, 1, 6}
  ]

  @impl true
  def meta, do: @meta

  defp tau, do: :math.pi() * 2

  defp cell(x, y), do: JSMath.round(x) + (JSMath.round(y - 0.01) >>> 1) * @meta.cols

  defp bearing(x, y), do: JSMath.mod(:math.atan2(x - @cx, @cy - y) + tau(), tau())

  # Each point and its mirror images across both axes, so every ring is symmetric.
  defp four(x, y) do
    c = JSMath.round(x)
    p = JSMath.round(y - 0.01)
    [{c, p}, {2 * @cx - c, p}, {c, @cy2 - p}, {2 * @cx - c, @cy2 - p}]
  end

  @impl true
  def init(%{range: range, unit: unit} = options) do
    %{cols: cols, rows: rows} = @meta
    # Each cell behind the sweep as {character, part}.
    back = bezel() |> rings() |> Map.put(cell(@cx, @cy), {"+", "ring"})

    back =
      [{"000", @cx - 1, 1}, {"180", @cx - 1, rows - 2}, {"270", 1, 12}, {"090", cols - 4, 12}]
      |> Enum.reduce(back, fn {s, c, r}, back ->
        s
        |> Text.chars()
        |> Enum.with_index(c + r * cols)
        |> Enum.into(back, fn {ch, i} -> {i, {ch, "scale"}} end)
      end)

    back = for i <- 0..(cols * rows - 1), do: Map.get(back, i, {" ", nil})
    land? = Map.get(options, :land, true)

    # Every cell inside the scope, with its bearing.
    inside =
      for r <- 0..(rows - 1),
          c <- 0..(cols - 1),
          JSMath.hypot(c - @cx, 2 * r + 0.5 - @cy) < @r - 0.3,
          do: {c + r * cols, bearing(c, 2 * r + 0.5)}

    land =
      for {i, b} <- inside,
          c = rem(i, cols),
          y = 2 * div(i, cols) + 0.5,
          land?(c, y, land?) do
        {i, b,
         Enum.any?([{1, 0}, {-1, 0}, {0, 2}, {0, -2}], fn {dx, dy} ->
           not land?(c + dx, y + dy, land?)
         end)}
      end

    %{
      back: List.to_tuple(back),
      inside: inside,
      land: land,
      land?: land?,
      tracks: tracks(Map.get(options, :contacts, []), range),
      top: [" brg ", "°", "rng #{JSMath.to_string(range)} #{unit} "],
      bottom: "rings #{JSMath.round(range / 3)} #{unit} "
    }
  end

  defp tracks([], _range) do
    for {h, off, v, u, size, gap} <- @tracks do
      l = 2 * :math.sqrt(@r * @r - off * off) + gap

      %{
        sin: :math.sin(h),
        cos: :math.cos(h),
        off: off,
        v: v,
        l: l,
        u0: u + l / 2,
        size: size
      }
    end
  end

  # Contacts given: where each stands, in pixels, the scope's range being
  # its radius. One at the edge is drawn just inside it, where upstream's
  # would still show.
  defp tracks(contacts, range) do
    for %{bearing: b, range: d} = contact <- placed(contacts, range) do
      a = b * :math.pi() / 180
      p = min(d / range * @r, @r - 1.3)
      %{at: {@cx + p * :math.sin(a), @cy - p * :math.cos(a)}, size: Map.get(contact, :size, 1)}
    end
  end

  # The contacts within the scope's range, that have a bearing and a range.
  defp placed(contacts, range) do
    for %{bearing: _, range: d} = contact <- contacts, range > 0 and d <= range, do: contact
  end

  # The bezel, a ring of half-block pixels just outside the scope.
  defp bezel do
    %{cols: cols, rows: rows} = @meta
    rb = @r + 1.5

    points =
      Enum.flat_map(0..20, fn dx -> four(@cx + dx, @cy - :math.sqrt(rb * rb - dx * dx)) end) ++
        Enum.flat_map(0..20, fn j ->
          dy = j + 0.5
          four(@cx + :math.sqrt(rb * rb - dy * dy), @cy - dy)
        end)

    ring =
      for {c, p} <- points,
          c >= 0 and c < cols and p >= 0 and p < rows * 2,
          into: MapSet.new(),
          do: c + p * cols

    on = fn i -> if MapSet.member?(ring, i), do: 1, else: 0 end

    for i <- 0..(cols * rows - 1),
        c = rem(i, cols),
        p = 2 * div(i, cols),
        k = on.(c + p * cols) ||| on.(c + (p + 1) * cols) <<< 1,
        k != 0,
        into: %{},
        do: {i, {elem(@half, k), "bezel"}}
  end

  # Two range rings, a dot in each cell they pass through, dropping the inner
  # corner of every step so the ring stays one cell thick.
  defp rings(back) do
    cols = @meta.cols

    for rr <- [@r / 3, 2 * @r / 3], reduce: back do
      back ->
        path =
          Enum.dedup(
            for i <- 0..200 do
              a = :math.pi() / 2 * (i / 200)
              x = @cx + rr * :math.sin(a)
              y = @cy - rr * :math.cos(a)
              {JSMath.round(x), JSMath.round(y - 0.01) >>> 1}
            end
          )

        nexts = Enum.drop(path, 2) ++ [nil]

        kept =
          path
          |> tl()
          |> Enum.zip(nexts)
          |> Enum.reduce([hd(path)], fn {cur, n}, [p | _] = kept ->
            if far?(p, n), do: [cur | kept], else: kept
          end)
          |> Enum.reverse()

        for {c, r} <- kept, {cc, pp} <- four(c, 2 * r + 0.5), reduce: back do
          back -> Map.put(back, cc + (pp >>> 1) * cols, {"·", "ring"})
        end
    end
  end

  defp far?(_p, nil), do: true
  defp far?({pc, pr}, {nc, nr}), do: abs(pc - nc) > 1 or abs(pr - nr) > 1

  # A coast along the south-west edge: land lies beyond this range at each bearing.
  defp shore(b),
    do:
      @r *
        (0.66 + 0.09 * :math.sin(b * 5 + 0.6) + 0.05 * :math.sin(b * 13) +
           2.2 * max(0, abs(b - 4.15) - 0.62))

  defp land?(_x, _y, false), do: false

  defp land?(x, y, true) do
    b = bearing(x, y)
    b > 3.3 and b < 5.0 and JSMath.hypot(x - @cx, y - @cy) > shore(b)
  end

  defp where(%{at: at}, _t), do: at

  defp where(%{sin: sin, cos: cos, off: off, v: v, l: l, u0: u0}, t) do
    u = JSMath.mod(JSMath.mod(u0 + v * t, l) + l, l) - l / 2
    {@cx + u * sin + off * cos, @cy - (u * cos - off * sin)}
  end

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    {out, corners} = draw(state, t)
    back = state.back

    lines =
      for r <- 0..(rows - 1) do
        Enum.map_join((r * cols)..(r * cols + cols - 1), fn i ->
          {ch, _part} = Map.get(out, i) || elem(back, i)
          ch
        end)
      end

    lines =
      Enum.reduce(corners, lines, fn {r, l, rt}, lines ->
        List.update_at(lines, r, &corner(&1, l, rt))
      end)

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # What the sweep, the land and the contacts lay over the scope at `t`, by
  # cell, as {character, part}; and the corners' texts by row.
  defp draw(state, t) do
    %{rows: rows} = @meta
    tau = tau()
    sweep = JSMath.mod(t / @turn * tau, tau)
    # Seconds since the beam passed.
    ago = fn b -> JSMath.mod(JSMath.mod(sweep - b, tau) + tau, tau) / tau * @turn end
    back = state.back

    # Land is a faint fill; its coast flares for a moment after each pass.
    out =
      Map.new(state.land, fn {i, b, edge} ->
        {i,
         {elem(@shade, if(edge and ago.(b) < 1.2, do: 2, else: 1)),
          if(edge, do: "land.coast", else: "land")}}
      end)

    # Afterglow: the beam itself, then a fading wedge behind it, over all but
    # the land.
    out =
      Enum.reduce(state.inside, out, fn {i, b}, out ->
        a = ago.(b) / @turn * tau

        cond do
          a >= @trail ->
            out

          a < 0.08 ->
            Map.put(out, i, {elem(@shade, 3), "sweep.beam"})

          a < 0.3 ->
            Map.put(out, i, {elem(@shade, 2), "sweep"})

          true ->
            {ch, _part} = Map.get(out, i) || elem(back, i)
            if shade_index(ch) >= 1, do: out, else: Map.put(out, i, {elem(@shade, 1), "sweep"})
        end
      end)

    # A contact shows where it was when the beam last crossed it, fading from
    # full to a mid shade, above anything the land or the trail can reach.
    {out, seen} =
      Enum.reduce(state.tracks, {out, 0}, fn track, {out, seen} ->
        {x0, y0} = where(track, t)
        s = ago.(bearing(x0, y0))
        {x, y} = where(track, t - s)

        if hidden?(track, x, y, state.land?) do
          {out, seen}
        else
          g = :math.exp(-s / @fade)
          ch = {elem(@shade, if(g > 0.7, do: 4, else: if(g > 0.42, do: 3, else: 2))), "contact"}
          i = cell(x, y)
          out = Map.put(out, i, ch)
          {if(track.size > 1, do: Map.put(out, i + 1, ch), else: out), seen + 1}
        end
      end)

    deg =
      (sweep * 180 / :math.pi())
      |> JSMath.round()
      |> rem(360)
      |> Integer.to_string()
      |> Text.pad_start(3, "0")

    [brg, degree, rng] = state.top

    {out, [{1, brg <> deg <> degree, rng}, {rows - 2, " contacts #{seen}", state.bottom}]}
  end

  # Upstream's contacts go out of sight near the bezel and over the land;
  # those given always show.
  defp hidden?(%{at: _}, _x, _y, _land?), do: false

  defp hidden?(_track, x, y, land?),
    do: JSMath.hypot(x - @cx, y - @cy) > @r - 1.2 or land?(x, y, land?)

  defp shade_index(ch) do
    Enum.find_index(Tuple.to_list(@shade), &(&1 == ch)) || -1
  end

  # Text in both corners of a line. Upstream lets a line overflow when the two
  # meet; here it is cut to the width.
  defp corner(line, l, rt) do
    cols = @meta.cols
    (l <> Text.slice(line, Text.length(l), cols - Text.length(rt)) <> rt) |> Text.slice(0, cols)
  end

  # This port's own: the parts of a frame, drawn again at its time. The
  # sweep, the land and the contacts are laid over the scope as frame/3 lays
  # them, each cell with its part, and the corners' texts are the readout.

  @impl true
  def parts(%{lines: lines, t: t}, options) do
    %{cols: cols} = @meta
    state = init(options)
    {out, corners} = draw(state, t)
    corners = Map.new(corners, fn {r, l, rt} -> {r, {Text.length(l), Text.length(rt)}} end)

    for {line, r} <- Enum.with_index(lines) do
      readout = Map.get(corners, r)

      Parts.cells(line, fn cp, c ->
        i = r * cols + c
        {ch, part} = Map.get(out, i) || elem(state.back, i)

        cond do
          readout?(readout, c) -> "readout"
          ch == <<cp::utf8>> -> part
          true -> nil
        end
      end)
    end
  end

  # Whether a cell is in a corner's text: the left one, then the right,
  # which the line is cut short to fit.
  defp readout?(nil, _c), do: false

  defp readout?({left, right}, c),
    do: c < left or c >= left + max(0, @meta.cols - right - left)

  @impl true
  def describe(%{contacts: []}), do: nil

  def describe(%{contacts: contacts, range: range, unit: unit}) do
    within = "within #{JSMath.to_string(range)} #{unit}" |> String.trim_trailing()

    case length(placed(contacts, range)) do
      0 -> "radar: no contacts " <> within
      1 -> "radar: 1 contact " <> within
      n -> "radar: #{n} contacts " <> within
    end
  end
end
