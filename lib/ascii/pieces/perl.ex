defmodule Ascii.Pieces.Perl do
  @moduledoc """
  The onion, glinting now and then.

  The Perl logo, an onion, with a glint crossing it every few seconds.

  Drawn from devicon's perl-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from perl-plain.svg. The
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

  `Ascii.describe/1` gives its name and note, "perl: the onion, glinting
  now and then". A player's or a component's `label` gives words of your own,
  as "the Perl logo".

  ## Example

  ```elixir
  still = Ascii.new!("perl", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("perl", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="perl" label="the Perl logo" />
  <Ascii.Phoenix.player socket={@socket} id="perl" piece="perl" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/perl.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "perl",
    category: :logos,
    note: "the onion, glinting now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#212178",
      "#fefefe",
      "#6f6fa7",
      "#fefefe",
      "#bcbcd7",
      "#ffffff",
      "#4f4fcf",
      "#fefefe",
      "#8d8de0",
      "#fefefe",
      "#cacaf1",
      "#ffffff"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

                    __ppq8888888888qqq__
                _pp8888888888d88888888888qq_
             _p888888888888P8d888888888888888q,
           _p88888888888888b8db"888888888888888q_
         _p8888888888888888P8|8|88888888888888888q,
        q888888888888888888\8|8"8888888888888888888p
       p88888888888888888P)8Pq8 "8888888888888888888q
      q8888888888888888"_p88'8P b_"Y88888888888888888q
     q88888888888888P"_p88P'q8|  "8q,"Y888888888888888p
    \888888888888P" _p888P q88     "8q_ "88888888888888,
    d8888888888P" .p888P" p88P       "88q, "88888888888b
    8888888888"  _8888" .p888'         "88p  "8888888888
    888888888'  q8888" .p888P           "88q, "888888888
    88888888"  )8888"  q8888'            "88p  )88888888
    88888888   88888   88888              888, '88888888
    O8888888   88888   8888b              888| .8888888P
    "8888888,  O8888,  88888             .888  |8888888"
     )888888q, '8888p  "8888,            q88" .8888888P
      O888888q, "8888p  "888p           _88" _p888888P
       O8888888_  Y888q_ "888,         _8P" q8888888P
        "88888888q_'"888q_'88p       _pP"_p88888888"
         '888888888qq_"Y88qq888qq_   "_pp88888888P'
           "888888888888q8888P88888q88888888888P"
             'Y88888888888P_8bd8_888888888888P'
                ""888888888888888888888888"'
                    '"Y8888888888888PP"'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __ppq8888888888qqq__
                _pp8888888888888888888888qq_
             _p888888888888888888888888888888q,
           _p8888888888888888888888888888888888q_
         _p88888888888888888888888888888888888888q,
        q888888888888888888888888888888888888888888p
       p88888888888888888888888888888888888888888888q
      q8888888888888888888888888888888888888888888888q
     q888888888888888888888888888888888888888888888888p
    \88888888888888888888888888888888888888888888888888,
    d88888888888888888888888888888888888888888888888888b
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    O88888888888888888888888888888888888888888888888888P
    "88888888888888888888888888888888888888888888888888"
     )888888888888888888888888888888888888888888888888P
      O8888888888888888888888888888888888888888888888P
       O88888888888888888888888888888888888888888888P
        "888888888888888888888888888888888888888888"
         '888888888888888888888888888888888888888P'
           "88888888888888888888888888888888888P"
             'Y888888888888888888888888888888P'
                ""888888888888888888888888"'
                    '"Y8888888888888PP"'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000000000000000000000000000
           00000000000000000010100000000000000000
         000000000000000000001010000000000000000000
        00000000000000000001010100000000000000000000
       0000000000000000000100101100000000000000000000
      000000000000000001100010010110000000000000000000
     00000000000000001100001001111011100000000000000000
    0000000000000011100000100011111100111000000000000000
    0000000000001110000011000011111111001111000000000000
    0000000000111100001110000111111111110011110000000000
    0000000001111000011100001111111111111000111000000000
    0000000011110000111000001111111111111100011100000000
    0000000011100000111000001111111111111100011100000000
    0000000011100000111000001111111111111100011100000000
    0000000011100000111000001111111111111100011100000000
     00000000111000001110000111111111111110011100000000
      000000001110000011100011111111111110011100000000
       0000000011100000111000111111111110011100000000
        00000000011110000110001111111100111000000000
         000000000000110000000000111111000000000000
           00000000000000000000000000000000000000
             0000000000000010000100000000000000
                0000000000000000000000000000
                    00000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
