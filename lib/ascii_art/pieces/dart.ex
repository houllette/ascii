defmodule AsciiArt.Pieces.Dart do
  @moduledoc """
  The dart, in blue and teal, glinting now and then.

  The Dart logo, the dart, in blue and teal, with a glint crossing it every
  few seconds.

  Drawn from devicon's dart-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from dart-plain.svg. The
  logo is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `AsciiArt.loop/1`).

  The picture is always 56 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "dart: the dart, in blue and
  teal, glinting now and then". A player's or a component's `label` gives
  words of your own, as "the Dart logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("dart", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("dart", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="dart" label="the Dart logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="dart" piece="dart" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/dart.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "dart",
    category: :logos,
    note: "the dart, in blue and teal, glinting now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#00c4b3",
      "#0075c9",
      "#00a8e1",
      "#22d3c5",
      "#59d9ce",
      "#59a5dc",
      "#59c6ec",
      "#6fe2d9",
      "#b3ede8",
      "#b3d6ef",
      "#b3e5f6",
      "#bdf2ee",
      "#00c4b3",
      "#0075c9",
      "#00a8e1",
      "#22d3c5",
      "#59d9ce",
      "#59a5dc",
      "#59c6ec",
      "#6fe2d9",
      "#b3ede8",
      "#b3d6ef",
      "#b3e5f6",
      "#bdf2ee"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

                            __p88q_
                         _pp88888888_
                      _pp8888888888888p,
                   _pp888888888888888888p
                _pp8888888888888888888888,
                ._________________________ _,
             q|q_"888888888888888888888888,Y8q_,
           _p8|d88_"8888888888888888888888b 8888q,
          _888|d8888_"888888888888888888888p"88888q,
         q8888|d888888_"88888888888888888888,)888888q,
       .p88888|d88888888_"8888888888888888888,88888888q,
      _8888888|d8888888888_"88888888888888888p'88888888b
     q88888888|d888888888888_"8888888888888888("8888888b
    q888888888|d88888888888888_"888888888888888,O888888b
    )888888888|d8888888888888888_"8888888888888p'888888b
     "88888888|d888888888888888888_"888888888888p"88888b
       "888888|d88888888888888888888_"88888888888,Y8888b
         "8888|d8888888888888888888888_"888888888b 8888b
           "Y8()888888888888888888888888_"88888888p"888b
               )q__"Y888888888888888888888_"888888"q888b
                )888qq__""O88888888888888888_"888"\8888b
                 "88888888qq__"Y88888888888888_""_88P""'
                   "888888888888qq__"Y8888888P"_,
                     "888888888888888qqq_"__pp8P
                       "88888888888888888888888'
                         "88888888888888888888P

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                            __p88q_
                         _pp88888888_
                      _pp8888888888888p,
                   _pp888888888888888888p
                _pp8888888888888888888888,
              _p88888888888888888888888888__,
             q8888888888888888888888888888888q_,
           _p88888888888888888888888888888888888q,
          _888888888888888888888888888888888888888q,
         q888888888888888888888888888888888888888888q,
       .p888888888888888888888888888888888888888888888q,
      _888888888888888888888888888888888888888888888888b
     q8888888888888888888888888888888888888888888888888b
    q88888888888888888888888888888888888888888888888888b
    )88888888888888888888888888888888888888888888888888b
     "8888888888888888888888888888888888888888888888888b
       "88888888888888888888888888888888888888888888888b
         "888888888888888888888888888888888888888888888b
           "Y888888888888888888888888888888888888888888b
               "888888888888888888888888888888888888888b
                )88888888888888888888888888888888888888b
                 "8888888888888888888888888888888888P""'
                   "8888888888888888888888888888(
                     "8888888888888888888888888P
                       "88888888888888888888888'
                         "88888888888888888888P

  """

  @ink ~S"""

                            0000000
                         000000000000
                      000000000000000000
                   0000000000000000000000
                00000000000000000000000000
              1011111111111111111111111111222
             11001111111111111111111111111122222
           111100001111111111111111111111112222222
          111110000001111111111111111111111122222222
         111111000000001111111111111111111111222222222
       1111111100000000001111111111111111111112222222222
      11111111100000000000011111111111111111112222222222
     111111111100000000000000111111111111111111222222222
    1111111111100000000000000001111111111111111122222222
    1111111111100000000000000000011111111111111122222222
     111111111100000000000000000000111111111111112222222
       1111111100000000000000000000001111111111111222222
         11111100000000000000000000000011111111111222222
           111100000000000000000000000000111111111122222
               33300000000000000000000000001111111122222
                3333333300000000000000000000011111222222
                 333333333333300000000000000000112222222
                   333333333333333300000000000033
                     333333333333333333330033333
                       3333333333333333333333333
                         3333333333333333333333

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
