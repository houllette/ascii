defmodule Ascii.Pieces.Clojure do
  @moduledoc """
  A lambda in a green and blue circle, glinting now and then.

  The Clojure logo, a lambda in a green and blue circle, with a glint crossing
  it every few seconds.

  Drawn from devicon's clojure-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is the same drawing. The
  logo is a trademark of its owner, shown here to name the language.

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

  `Ascii.describe/1` gives its name and note, "clojure: a lambda in a green
  and blue circle, glinting now and then". A player's or a component's `label`
  gives words of your own, as "the Clojure logo".

  ## Example

  ```elixir
  still = Ascii.new!("clojure", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("clojure", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="clojure" label="the Clojure logo" />
  <Ascii.Phoenix.player socket={@socket} id="clojure" piece="clojure" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/clojure.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "clojure",
    category: :logos,
    note: "a lambda in a green and blue circle, glinting now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#ffffff",
      "#5881d8",
      "#91dc48",
      "#90b4fe",
      "#63b132",
      "#ffffff",
      "#92ade6",
      "#b8e888",
      "#b7cefe",
      "#9acc7a",
      "#ffffff",
      "#cdd9f3",
      "#def5c8",
      "#dee9ff",
      "#d0e8c2",
      "#ffffff",
      "#5881d8",
      "#91dc48",
      "#90b4fe",
      "#63b132",
      "#ffffff",
      "#92ade6",
      "#b8e888",
      "#b7cefe",
      "#9acc7a",
      "#ffffff",
      "#cdd9f3",
      "#def5c8",
      "#dee9ff",
      "#d0e8c2"
    ],
    loop: 5
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "",
            "                    ___pppppqqqqq__,",
            "                _pp888888888888888888qq_",
            "             _p88888888888888888888888888q_",
            "           _p888888888888888888888888888888q_",
            "         _dP\"\"\"\"\"\"\"Y88888PPPPP888888888888888q_",
            "                      '  .____,  '\"Y88888888888p",
            "          __ppppqp      \"8888888qq_  \"8888888888q,",
            "        _p888888\" .p88p  '8888888888q, \"888888888p",
            "      _8888888P' _88888q, '88888888888_ '888888888p",
            "     q88888888' )88888888, \"88888888888( '888888888,",
            "    \\88888888( .888888888b, 888888888888, |88888888|",
            "    q88888888' |888888888P' \"88888888888| '88888888p",
            "    d88888888, |88888888P'_, )8888888888| .88888888P",
            "    |88888888p '8888888P _8b  8888888888' |88888888|",
            "     888888888, \"88888P .888p '88888888\" .88888888P",
            "     )88888888q, \"888P  q8888, '888888\" .p8888888P",
            "      O888888888_  Y8' :888888,  \"88P' _8888888\"'",
            "       8888888888q_    |8888888_      '\"\"\"\"\"'",
            "        Y88888888888q_,  ''''''  ___,        __",
            "         \"88888888888888qqqqqppp88888888888888\"",
            "           \"88888888888888888888888888888888\"",
            "             \"Y88888888888888888888888888P\"",
            "                \"\"88888888888888888888\"\"",
            "                    '\"\"^YP8888PP^\"\"'",
            "",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    .__ppq88888888qqq__,
                __p8888888888888888888888q_,
             ._p8888888888888888888888888888q_,
           _p8888888888888888888888888888888888q,
         .p88888888888888888888888888888888888888q,
        _888888888888888888888888888888888888888888_
       q88888888888888888888888888888888888888888888p
      q8888888888888888888888888888888888888888888888p
     q888888888888888888888888888888888888888888888888p
    .88888888888888888888888888888888888888888888888888,
    q88888888888888888888888888888888888888888888888888p
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    d88888888888888888888888888888888888888888888888888P
    '88888888888888888888888888888888888888888888888888'
     "888888888888888888888888888888888888888888888888"
      )8888888888888888888888888888888888888888888888P
       )88888888888888888888888888888888888888888888P
        "888888888888888888888888888888888888888888"
          Y88888888888888888888888888888888888888P
           'Y8888888888888888888888888888888888P'
              "88888888888888888888888888888P"
                '"Y8888888888888888888888P"'
                     ""YP8888888888PP""

  """

  @ink ~S"""

                    00000000000000000000
                0000000000111111110000000000
             0000000111111111111111111110000000
           00000111111111111111111111111111100000
         000001111111111111111111111111111111100000
        00001100000001111111111111111111111111110000
       0000000000000000000000000000001111111111111000
      000000004444400000000333333333000011111111111000
     00000044444440000220000333333333330001111111111000
    0000044444444000222222000333333333330001111111110000
    0000444444440002222222200033333333333000111111111000
    0004444444400022222222220033333333333300011111111000
    0004444444400022222222220003333333333300011111111000
    0004444444400022222222200003333333333300011111111000
    0004444444400022222222002200333333333300011111111000
    0004444444440002222220022200033333333000111111111000
    0000444444444000222200222220003333330001111111100000
     00044444444440002200022222200003330001111111000000
      000444444444440000002222222000000000000000000000
       0004444444444444000000000000000000000000000000
        00004444444444444444444444444444444444440000
          0000444444444444444444444444444444440000
           00000444444444444444444444444444400000
              00000044444444444444444444000000
                0000000000444444440000000000
                     000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
