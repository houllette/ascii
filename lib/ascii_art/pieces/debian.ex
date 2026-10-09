defmodule AsciiArt.Pieces.Debian do
  @moduledoc """
  The red swirl, scanned now and then.

  The Debian logo, the swirl, with a scan line running down it every few
  seconds that scrambles what it passes.

  Drawn from devicon's debian-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from devicon's
  debian-plain.svg (MIT). The logo is a trademark of its owner, shown here to
  name the distribution.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `scan` - seconds from one scan to the next, 0 to 3600; default 5. A line
      two rows deep takes two seconds to run down the logo, scrambling the
      characters it covers, with five rows of afterglow behind it, so it comes
      at most every two and a half; 0 keeps the logo still.

  The picture is always 46 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "debian: the red swirl,
  scanned now and then". A player's or a component's `label` gives words of
  your own, as "the Debian logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("debian", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("debian", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {46, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="debian" label="the Debian logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="debian" piece="debian" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/debian.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "debian",
    category: :distros,
    note: "the red swirl, scanned now and then",
    cols: 46,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#a80030",
      "#c65978",
      "#e5b3c1",
      "#c20037",
      "#d7597d",
      "#edb3c3"
    ]
  }

  # In one ink.
  @mono ~S"""

                   _pppqq____q__
               _pp888888888888888qpqp,
            _p888888888PPPPYP8888888888q,
          _p8888888P"            "Y888888q,
         p888888"                   "888888p
     _  q888P"                        Y88888p
      _p88P"                           )888"O
    ,_888"             ._pp0OOo(,       O888 :
    'd88P             q8"'      ''      "888,
    q88P            .pP                  888,
    |88P            qP             ,     888"
    q88|            8|                  '88P
    |88'            8b           _.     q88'
    d88.            )8p      __        q88'
    |88p           ~,"8q,            _p8Y
    '88b            ""("8q__    __pq8P"
     d88,              "YdPP88888P""'
     '8888p                '"^^'
      "888q
       "888p
        '888p
          "88q,
           'Y88q_
             'Y88q,
                "Y8qq_
                   '"YOo___,

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                   __ppqq____q__
               _pp888888888888888qpqp,
            _p888888888PPPPYP8888888888q,
          _p8888888P"            "Y888888q,
         p888888"                   "888888p
     _  q8888"                        Y88888p
      _p888"                           )888"O
    ,_888"             ._pp0OOo(,       O888 :
    'd88P             q8"'      ''      "888,
    q888            .pP                  888,
    |88P            qP             ,     888"
    |88|            8|                  '88P
    |88'            8b           _.     q88'
    |88,            )8p      __        q88'
    |88p           ~,"8q,            _p8Y
    '88b            ""("8q__    __pq88"
     d88,              "YdPP88888PY"'
     '8888p                '"^^'
      "888q'
       "888p
        '888p
          "88q,
           'Y88q_
             'Y88q,
                "Y8qq_
                   '"YOo___,

  """

  @ink ~S"""

                   0000000000000
               00000000000000000000000
            00000000000000000000000000000
          00000000000            0000000000
         00000000                   00000000
     0  000000                        0000000
      000000                           000000
    000000             0000000000       0000 0
    00000             0000      00      00000
    0000            000                  0000
    0000            00             0     0000
    0000            00                  0000
    0000            00           00     0000
    0000            000      00        0000
    0000           000000            0000
    0000            00000000    0000000
     0000              00000000000000
     000000                00000
      000000
       00000
        00000
          00000
           000000
             000000
                000000
                   000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
