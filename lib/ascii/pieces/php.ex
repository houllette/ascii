defmodule Ascii.Pieces.Php do
  @moduledoc """
  Php in its purple oval, glinting now and then.

  The PHP logo, php in an oval, with a glint crossing it every few seconds.

  Drawn from devicon's php-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from php-plain.svg. The logo
  is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 69 by 19.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "php: php in its purple oval,
  glinting now and then". A player's or a component's `label` gives words of
  your own, as "the PHP logo".

  ## Example

  ```elixir
  still = Ascii.new!("php", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("php", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {69, 19, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="php" label="the PHP logo" />
  <Ascii.Phoenix.player socket={@socket} id="php" piece="php" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/php.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "php",
    category: :logos,
    note: "php in its purple oval, glinting now and then",
    cols: 69,
    rows: 19,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#abafd0",
      "#000000",
      "#494d88",
      "#fefefe",
      "#777bb3",
      "#65699d",
      "#c8cbe0",
      "#595959",
      "#898bb2",
      "#fefefe",
      "#a7a9ce",
      "#9b9ebf",
      "#e6e7f1",
      "#b3b3b3",
      "#c8cadb",
      "#ffffff",
      "#d6d7e8",
      "#d1d2e2",
      "#abafd0",
      "#000000",
      "#54589c",
      "#fefefe",
      "#777bb3",
      "#65699d",
      "#c8cbe0",
      "#595959",
      "#9092bf",
      "#fefefe",
      "#a7a9ce",
      "#9b9ebf",
      "#e6e7f1",
      "#b3b3b3",
      "#cccde1",
      "#ffffff",
      "#d6d7e8",
      "#d1d2e2"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                      ___ppppq8888888888888qqqqq___
                __pp888888888888888888888888888888888qq__
            _pp888888888888888888P"""888888888888888888888qq_
         _p8888888888888888888888'  |8888888888888888888888888q_
       _p88888888888888888888888P   d888888888888888888888888888q_
     .p8888888888|          'Y88|          '88|          "Y8888888q,
    .p88888888888'  |8888q,   d8   q8888p   |8   |8888q,   O8888888q,
    q88888888888P   d88888P   qP   d8888P   dP   d88888P   q88888888p
    888888888888"  .888888"  .8'  |88888"  .8'  .888888'  .8888888888
    d88888888888   )PPPP"'  _pP   q88888   q8   )PPPP"   _p888888888P
     8888888888P        ___p88|   88888P   8|        ___p88888888888
      O88888888'  |8888888888888888888888888'  |888888888888888888P
       "888888P   q888888888888888888888888P   d8888888888888888P"
         'Y8888qqq88888888888888888888888888qqq888888888888888P'
            '"88888888888888888888888888888888888888888888P"'
                '"Y88888888888888888888888888888888888P"'
                      '"""Y888888888888888888PP"""'

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                      ___ppppq8888888888888qqqqq___
                __pp888888888888888888888888888888888qq__
            _pp8888888888888888888888888888888888888888888qq_
         _p888888888888888888888888888888888888888888888888888q_
       _p8888888888888888888888888888888888888888888888888888888q_
     .p88888888888888888888888888888888888888888888888888888888888q,
    .p8888888888888888888888888888888888888888888888888888888888888q,
    q888888888888888888888888888888888888888888888888888888888888888p
    88888888888888888888888888888888888888888888888888888888888888888
    d888888888888888888888888888888888888888888888888888888888888888P
     888888888888888888888888888888888888888888888888888888888888888
      O88888888888888888888888888888888888888888888888888888888888P
       "88888888888888888888888888888888888888888888888888888888P"
         'Y888888888888888888888888888888888888888888888888888P'
            '"88888888888888888888888888888888888888888888P"'
                '"Y88888888888888888888888888888888888P"'
                      '"""Y888888888888888888PP"""'

  '''

  @ink ~S"""

                      00000000000000000004444444555
                00000044444444444444444444444444444522222
            0000444444444444444443111344444444444444444442222
         0000444444444444444444431111444444444444444444444442222
       00044444443444444444444443111134444444434444444444444444222
     400444444444111111111111344111111111111341111111111113444444222
    44444444444431111344431111331111344431111311113444311113444444222
    44444444444431113444443111131113444431113311134444431113444444422
    44444444444411113444431111311113444411113111134444311113444444442
    44444444444311113311111113311134444311113111133111111134444444422
     444444444411111111111134411113444411113111111111111344444444422
      4444444431111344444444444444444444444311113444444444444444422
       44444443111344444444444444444444444431113444444444444444222
         5444434444444444444444444444444444344444444444444442222
            5544444444444444444444444444444444444444444442222
                55555544444444444444444444444444444222222
                      55555555555422222222222222222

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
