defmodule Ascii.Pieces.Kotlin do
  @moduledoc """
  The k, in violet and pink, glinting now and then.

  The Kotlin logo, a K cut from a square, with a glint crossing it every few
  seconds.

  Drawn from devicon's kotlin-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from
  kotlin-plain.svg. The logo is a trademark of its owner, shown here to name
  the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 56 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "kotlin: the k, in violet and
  pink, glinting now and then". A player's or a component's `label` gives
  words of your own, as "the Kotlin logo".

  ## Example

  ```elixir
  still = Ascii.new!("kotlin", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("kotlin", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="kotlin" label="the Kotlin logo" />
  <Ascii.Phoenix.player socket={@socket} id="kotlin" piece="kotlin" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/kotlin.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "kotlin",
    category: :logos,
    note: "the k, in violet and pink, glinting now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#c01ae1",
      "#963df5",
      "#d124b1",
      "#ac2aec",
      "#db3683",
      "#d66aec",
      "#bb81f9",
      "#e171cc",
      "#c975f3",
      "#e87cae",
      "#ecbaf6",
      "#e0c5fc",
      "#f1bde8",
      "#e6bff9",
      "#f4c3da",
      "#c01ae1",
      "#963df5",
      "#d124b1",
      "#ac2aec",
      "#db3683",
      "#d66aec",
      "#bb81f9",
      "#e171cc",
      "#c975f3",
      "#e87cae",
      "#ecbaf6",
      "#e0c5fc",
      "#f1bde8",
      "#e6bff9",
      "#f4c3da"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

    88888888888888888888888888888888888888888888888888P"
    888888888888888888888888888888888888888888888888P"
    8888888888888888888888888888888888888888888888P"
    88888888888888888888888888888888888888888888P"
    888888888888888888888888888888888888888888P"
    8888888888888888888888888888888888888888P"
    88888888888888888888888888888888888888P"
    888888888888888888888888888888888888P"
    8888888888888888888888888888888888P"
    88888888888888888888888888888888P"
    888888888888888888888888888888P"
    8888888888888888888888888888P"
    88888888888888888888888888P"
    88888888888888888888888888q_
    8888888888888888888888888888q_
    888888888888888888888888888888q_
    88888888888888888888888888888888q_
    8888888888888888888888888888888888q_
    888888888888888888888888888888888888q_
    88888888888888888888888888888888888888q_
    8888888888888888888888888888888888888888q_
    888888888888888888888888888888888888888888q_
    88888888888888888888888888888888888888888888q_
    8888888888888888888888888888888888888888888888q_
    888888888888888888888888888888888888888888888888q_
    88888888888888888888888888888888888888888888888888q_

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

    88888888888888888888888888888888888888888888888888P"
    888888888888888888888888888888888888888888888888P"
    8888888888888888888888888888888888888888888888P"
    88888888888888888888888888888888888888888888P"
    888888888888888888888888888888888888888888P"
    8888888888888888888888888888888888888888P"
    88888888888888888888888888888888888888P"
    888888888888888888888888888888888888P"
    8888888888888888888888888888888888P"
    88888888888888888888888888888888P"
    888888888888888888888888888888P"
    8888888888888888888888888888P"
    88888888888888888888888888P"
    88888888888888888888888888q_
    8888888888888888888888888888q_
    888888888888888888888888888888q_
    88888888888888888888888888888888q_
    8888888888888888888888888888888888q_
    888888888888888888888888888888888888q_
    88888888888888888888888888888888888888q_
    8888888888888888888888888888888888888888q_
    888888888888888888888888888888888888888888q_
    88888888888888888888888888888888888888888888q_
    8888888888888888888888888888888888888888888888q_
    888888888888888888888888888888888888888888888888q_
    88888888888888888888888888888888888888888888888888q_

  """

  @ink ~S"""

    0000000000000222222222222222244444444444444444444444
    00000000000000022222222222222224444444444444444444
    000000000000000002222222222222222444444444444444
    0000000000000000000222222222222222244444444444
    00000000000000000000022222222222222224444444
    000000000000000000000002222222222222222444
    3300000000000000000000000222222222222222
    33330000000000000000000000022222222222
    333333000000000000000000000002222222
    3333333300000000000000000000000222
    33333333330000000000000000000000
    333333333333000000000000000000
    3333333333333300000000000000
    1333333333333333000000000000
    111333333333333333000000000000
    11111333333333333333000000000000
    1111111333333333333333000000000000
    111111111333333333333333000000000000
    11111111111333333333333333000000000000
    1111111111111333333333333333000000000000
    111111111111111333333333333333000000000000
    11111111111111111333333333333333000000000000
    1111111111111111111333333333333333000000000000
    111111111111111111111333333333333333000000000000
    11111111111111111111111333333333333333000000000000
    1111111111111111111111111333333333333333000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
