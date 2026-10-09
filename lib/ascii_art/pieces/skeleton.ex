defmodule AsciiArt.Pieces.Skeleton do
  @moduledoc """
  A loading card in shade blocks with a shimmer passing over.

  The loading placeholder for a card. An avatar, a name and a byline, an
  image and lines of text in light shade, with a shimmer sweeping across
  them while the content is on its way. Its options shape the card to the
  one it stands in for.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): the card
  is laid out anew from them, and the shimmer carries on, being a function
  of play time.

    * `avatar` - a round avatar, with a name and a byline beside it; `false`
      leaves a title and a shorter line in its place. Default `true`.
    * `image` - an image block under the head. Default `true`.
    * `lines` - lines of text under them, the last cut short like the end
      of a paragraph; taken as its integer part, as upstream floors it, and
      as many as fit: three under an avatar and an image, six without the
      image, four without the avatar, eight with neither. Default 3.

  The frame is always 52 by 23, the card as tall as its blocks and centred
  in it.

  ## Colours

  It has no parts to colour one by one: in one ink, or a gradient, with
  `:ink` and `:gradient` (see `AsciiArt.Ink`). On a light page (`paper:
  true`) the shimmer lifts the shade toward the page rather than darkening
  it.

  ## Keys and clicks

  It takes none: it stands in for content, and `AsciiArt.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked.

  ## Screen readers

  `AsciiArt.describe/1` gives the piece's name and note, "skeleton: a
  loading card in shade blocks with a shimmer passing over"; give a player
  a `label` of your own, as "loading the profile", to say what is coming.

  ## Example

  ```elixir
  card = AsciiArt.new!("skeleton", options: %{avatar: false, lines: 2}, ink: "#8b949e")
  {frame, _card} = AsciiArt.frame(card, 0.5)
  {frame.cols, frame.rows}
  #=> {52, 23}

  Enum.count(frame.lines, &(&1 =~ ~r/[░▒▓]/u))
  #=> 10
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="loading" piece="skeleton" options={%{image: false}} label="loading the profile" />
  ```

  Ported from `src/pieces/skeleton.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "skeleton",
    category: :ui,
    note: "a loading card in shade blocks with a shimmer passing over",
    cols: 52,
    rows: 23,
    fps: 24,
    options: %{lines: 3, image: true, avatar: true}
  }

  # Seconds from one sweep to the next; where in the sweep play time begins;
  # columns the band leans per row.
  @period 1.8
  @start 0.3
  @slant 0.8
  # The content's first and last column inside the card.
  @left 3
  @right 48

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{lines: lines, image: image, avatar: avatar}) do
    %{cols: cols, rows: rows} = @meta
    full = @right - @left + 1

    # Each block is {height, [{row, first column, last column}]}.
    blocks =
      [head(avatar)] ++ if(image, do: [{6, for(r <- 0..5, do: {r, @left, @right})}], else: [])

    # As many lines as fit, the last one cut short like the end of a paragraph.
    used = Enum.reduce(blocks, 0, fn {h, _}, a -> a + h + 1 end)
    n = max(0, min(floor(lines), floor((rows - 4 - used + 1) / 2)))

    blocks =
      if n > 0 do
        runs =
          for i <- 0..(n - 1) do
            f =
              cond do
                i == n - 1 and n == 1 -> 0.72
                i == n - 1 -> 0.58
                true -> elem({1, 0.91, 0.96, 0.87}, rem(i, 4))
              end

            {i * 2, @left, @left + JSMath.round(full * f) - 1}
          end

        blocks ++ [{n * 2 - 1, runs}]
      else
        blocks
      end

    # The card is as tall as its blocks and sits in the middle of the frame.
    inner = Enum.reduce(blocks, 0, fn {h, _}, a -> a + h end) + length(blocks) - 1
    h = inner + 4
    top = floor((rows - h) / 2)

    {mask, _} =
      Enum.reduce(blocks, {MapSet.new(), top + 2}, fn {bh, runs}, {mask, y} ->
        mask =
          for {r, c0, c1} <- runs,
              c <- c0..c1//1,
              k = (y + r) * cols + c,
              k >= 0 and k < cols * rows,
              into: mask,
              do: k

        {mask, y + bh + 1}
      end)

    base = border(top, h)
    mid = top + h / 2

    # Each cell: its fixed character, or for a shaded one the parts of its
    # distance from the band that do not move.
    cells =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          k = r * cols + c
          if k in mask, do: {c + 0.5, (mid - r) * @slant}, else: Map.get(base, k, " ")
        end
      end

    %{cells: cells}
  end

  defp head(true) do
    # A circle six rows tall, kept where a cell is at least half inside.
    runs =
      for r <- 0..5 do
        case for(c <- @left..(@left + 11), inside?(c, r), do: c) do
          [] -> {r, -1, -1}
          hits -> {r, hd(hits), List.last(hits)}
        end
      end

    # The name and byline sit level with the avatar's shoulders.
    {6, runs ++ [{1, @left + 15, @left + 32}, {4, @left + 15, @left + 26}]}
  end

  defp head(false), do: {3, [{0, @left, @left + 17}, {2, @left, @left + 10}]}

  # Whether at least half of a cell's 16 samples fall inside the avatar.
  defp inside?(c, r) do
    ax = @left + 6
    big_r = 3

    hits =
      for j <- 0..3, i <- 0..3, reduce: 0 do
        hit ->
          x = (c + 0.125 + i * 0.25 - ax) / 2
          y = r + 0.125 + j * 0.25 - big_r
          if x * x + y * y < big_r * big_r, do: hit + 1, else: hit
      end

    hits >= 8
  end

  # The card's rounded border never changes.
  defp border(top, h) do
    %{cols: cols} = @meta
    bot = top + h - 1

    base =
      for c <- 1..(cols - 2), k <- [top * cols + c, bot * cols + c], into: %{}, do: {k, "─"}

    base =
      for r <- (top + 1)..(bot - 1)//1,
          k <- [r * cols, r * cols + cols - 1],
          into: base,
          do: {k, "│"}

    Map.merge(base, %{
      (top * cols) => "╭",
      (top * cols + cols - 1) => "╮",
      (bot * cols) => "╰",
      (bot * cols + cols - 1) => "╯"
    })
  end

  @impl true
  def frame(%{cells: cells} = state, t, env) do
    # Base, edge of the band, its one-cell core. On a dark page the band
    # brightens the shade; on paper it lifts it toward the page.
    {base, edge, core} = if env.paper, do: {"▒", "░", "·"}, else: {"░", "▒", "▓"}
    # The band runs from just off the left edge to just off the right, so the wrap is unseen.
    x = -12 + JSMath.mod(t / @period + @start, 1) * (@meta.cols + 24)

    lines =
      for row <- cells do
        for cell <- row do
          case cell do
            {c5, s} ->
              d = abs(c5 - x - s)

              cond do
                d < 0.5 -> core
                d < 4.5 -> edge
                true -> base
              end

            ch ->
              ch
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
