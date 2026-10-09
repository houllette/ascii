defmodule Ascii.Pieces.Dividers do
  @moduledoc """
  Rules and ornaments for between sections, plain to fancy.

  A sheet of rules to set between sections of a page, from a plain line
  through short centred rules down to ornaments, chains and waves. For one
  rule of your own, as wide as you like and with a label in it, see
  `Ascii.Compose.divider/2`.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the
  sheet is drawn anew at the new measure.

    * `width` - the rules' measure in cells, 13 to the sheet's 63; the
      ornaments run a fraction of it each, so they shrink with it. Default
      `59`; `0` takes the default.

  The sheet is always 63 by 25, its rules centred, and still (0 frames a
  second).

  ## Colours

  It has no parts to colour one by one: in one ink, or a gradient, with
  `:ink` and `:gradient` (see `Ascii.Ink`). A vertical gradient gives
  each rule a colour of its own.

  ## Keys and clicks

  It takes none: it is a sheet to copy from, and `Ascii.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked.

  ## Screen readers

  `Ascii.describe/1` gives the piece's name and note: "dividers: rules
  and ornaments for between sections, plain to fancy".

  ## Example

  ```elixir
  {:ok, sheet} = Ascii.still("dividers", options: %{width: 31}, ink: "#8b949e")
  sheet.lines |> Enum.at(1) |> String.trim()
  #=> "───────────────────────────────"

  # One rule of your own, with a label in it.
  Ascii.Compose.divider(24, label: "logs", style: :dashed).lines
  #=> ["┄┄ logs ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"]
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="dividers" options={%{width: 41}} ink="#8b949e" />
  ```

  Ported from `src/pieces/dividers.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "dividers",
    category: :ui,
    note: "rules and ornaments for between sections, plain to fancy",
    cols: 63,
    rows: 25,
    fps: 0,
    options: %{width: 59}
  }

  # The same string seen in a mirror, so its slanted and pointed glyphs turn too.
  @flip %{
    "<" => ">",
    ">" => "<",
    "╱" => "╲",
    "╲" => "╱",
    "╶" => "╴",
    "╴" => "╶",
    "╡" => "╞",
    "╞" => "╡"
  }

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{width: width}) do
    %{cols: cols, rows: rows} = @meta
    # Math.floor(width) || 59: a width that floors to zero takes the default.
    w = max(13, min(cols, if(floor(width) == 0, do: 59, else: floor(width))))
    # The ornaments run a fraction of the measure, so they shrink with it.
    part = fn f -> max(5, JSMath.round(w * f)) end

    sheet = [
      rep("─", w),
      rep("═", w),
      rep("· ", odd(w)),
      # A short rule, centred.
      rep("━", odd(part.(0.25))),
      tapered(w),
      around(" · ° · ", "─", w),
      "*     *     *",
      sym("╶" <> rep("─", (odd(part.(0.5)) - 5) / 2) <> " ", "°"),
      around("╡ ° ╞", "═", odd(part.(0.7))),
      sym(rep("─<>", floor((part.(0.73) - 1) / 6) * 3), "─"),
      # Even, so it ends on the half it began with, mirrored.
      rep("╱╲", part.(0.55) - rem(part.(0.55), 2)),
      rep("_.·°·.", floor((part.(0.73) - 1) / 6) * 6) <> "_"
    ]

    sheet = List.to_tuple(sheet)

    lines =
      for r <- 0..(rows - 1) do
        # Even rows are blank, odd rows take the sheet in turn.
        i = div(r - 1, 2)
        s = if rem(r, 2) == 1 and i < tuple_size(sheet), do: elem(sheet, i), else: ""
        left = floor((cols - Text.length(s)) / 2)
        (String.duplicate(" ", max(0, left)) <> s) |> Text.pad_end(cols) |> Text.slice(0, cols)
      end

    IO.iodata_to_binary(Enum.intersperse(lines, ?\n))
  end

  defp odd(n), do: if(rem(n, 2) != 0, do: n, else: n - 1)

  # `unit` repeated to n characters.
  defp rep(unit, n) do
    len = Text.length(unit)
    unit |> Text.repeat(max(0, ceil(n / len))) |> Text.slice(0, max(0, trunc(n)))
  end

  defp mirror(s),
    do: s |> String.codepoints() |> Enum.reverse() |> Enum.map_join(&Map.get(@flip, &1, &1))

  # A left half, an optional middle cell and the half again in the mirror.
  defp sym(half, mid), do: half <> mid <> mirror(half)

  # A centrepiece with a rule run out to either side, n wide.
  defp around(mid, fill, n) do
    len = Text.length(mid)
    side = floor((n - len) / 2)
    sym(rep(fill, side), if(len + 2 * side < n, do: fill <> mid, else: mid))
  end

  # Thin at the ends, heavy in the middle: dots, then dashes, then rules.
  defp tapered(n) do
    h = floor(n / 2)

    if h < 12 do
      rep("─", n)
    else
      run = h - 8
      thin = ceil(run * 0.45)

      sym(
        "· · ─ ─ " <> rep("─", thin) <> rep("━", run - thin),
        if(rem(n, 2) != 0, do: "━", else: "")
      )
    end
  end

  @impl true
  def frame(picture, _t, _env), do: {picture, nil, picture}
end
