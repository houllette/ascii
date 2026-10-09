defmodule AsciiArt.Pieces.RockyLinux do
  @moduledoc """
  The mountain in a green circle, scanned now and then.

  The Rocky Linux logo, a mountain cut from a green circle, with a scan line
  running down it every few seconds that scrambles what it passes.

  Drawn from devicon's rockylinux-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is the same drawing. The
  logo is a trademark of its owner, shown here to name the distribution.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `scan` - seconds from one scan to the next, 0 to 3600; default 5. A line
      two rows deep takes two seconds to run down the logo, scrambling the
      characters it covers, with five rows of afterglow behind it, so it comes
      at most every two and a half; 0 keeps the logo still.

  The picture is always 56 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "rocky linux: the mountain in
  a green circle, scanned now and then". A player's or a component's `label`
  gives words of your own, as "the Rocky Linux logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("rocky-linux", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("rocky-linux", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="rocky-linux" label="the Rocky Linux logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="rocky-linux" piece="rocky-linux" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/rocky-linux.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "rocky linux",
    category: :distros,
    note: "the mountain in a green circle, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#10bd85",
      "#64d4b0",
      "#b7ebda",
      "#10bd85",
      "#64d4b0",
      "#b7ebda"
    ]
  }

  # In one ink.
  @mono ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
             _pp8888888888888888888888888888qq,
           _p8888888888888888888888888888888888q,
         _p88888888888888888888888888888888888888q,
        _888888888888888888888888888888888888888888_
       q88888888888888888888888888888888888888888888p
      q8888888888888888888888888888888888888888888888p
     q888888888888888888888888888888888888888888888888p
    .8888888888888888888888888888888P'"8888888888888888,
    q88888888888888888888888888888P'    "88888888888888p
    8888888888888888888888888888P'        "8888888888888
    88888888888888888888888888P'            "88888888888
    888888888888888888888888P'                "888888888
    8888888888888888888888P'                    "8888888
    d8888888888888888888P'           __           "8888P
    '88888888888888888P'           _888q_           "88'
     )88888888888888P'           _8888888q_           '
      Y88888888888P'           _88888888888q_
       Y88888888P'           _888888888888888q_
        "88888P'           _8888888888888888888q_
         'Y8P'           _88888888888888888888888P
                       _88888888888888888888888P'
                     _88888888888888888888888"'
                   \888888888888888888888P"'
                    '""Y888888888888P""'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
             _pp8888888888888888888888888888qq,
           _p8888888888888888888888888888888888q,
         _p88888888888888888888888888888888888888q,
        _888888888888888888888888888888888888888888_
       q88888888888888888888888888888888888888888888p
      q8888888888888888888888888888888888888888888888p
     q888888888888888888888888888888888888888888888888p
    .8888888888888888888888888888888P'"8888888888888888,
    q88888888888888888888888888888P'    "88888888888888p
    8888888888888888888888888888P'        "8888888888888
    88888888888888888888888888P'            "88888888888
    888888888888888888888888P'                "888888888
    8888888888888888888888P'                    "8888888
    d8888888888888888888P'           __           "8888P
    '88888888888888888P'           _888q_           "88'
     )88888888888888P'           _8888888q_           '
      Y88888888888P'           _88888888888q_
       Y88888888P'           _888888888888888q_
        "88888P'           _8888888888888888888q_
         'Y8P'           _88888888888888888888888P
                       _88888888888888888888888P'
                     _88888888888888888888888"'
                   \888888888888888888888P"'
                    '""Y888888888888P""'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000000000000000000000000000
           00000000000000000000000000000000000000
         000000000000000000000000000000000000000000
        00000000000000000000000000000000000000000000
       0000000000000000000000000000000000000000000000
      000000000000000000000000000000000000000000000000
     00000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000
    00000000000000000000000000000000    0000000000000000
    000000000000000000000000000000        00000000000000
    0000000000000000000000000000            000000000000
    00000000000000000000000000                0000000000
    000000000000000000000000                    00000000
    0000000000000000000000           00           000000
    00000000000000000000           000000           0000
     00000000000000000           0000000000           0
      00000000000000           00000000000000
       00000000000           000000000000000000
        00000000           0000000000000000000000
         00000           0000000000000000000000000
                       00000000000000000000000000
                     00000000000000000000000000
                   0000000000000000000000000
                    00000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
