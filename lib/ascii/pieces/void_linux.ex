defmodule Ascii.Pieces.VoidLinux do
  @moduledoc """
  The green ring, cut through, scanned now and then.

  The Void Linux logo, a ring cut through, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from Simple Icons' voidlinux.svg (CC0): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is the same drawing. The logo is a
  trademark of its owner, shown here to name the distribution.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
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
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "void linux: the green ring,
  cut through, scanned now and then". A player's or a component's `label`
  gives words of your own, as "the Void Linux logo".

  ## Example

  ```elixir
  still = Ascii.new!("void-linux", options: %{scan: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("void-linux", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="void-linux" label="the Void Linux logo" />
  <Ascii.Phoenix.player socket={@socket} id="void-linux" piece="void-linux" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/void-linux.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Distro

  @meta %Ascii.Meta{
    name: "void linux",
    category: :distros,
    note: "the green ring, cut through, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#478061",
      "#87ac98",
      "#c8d9d0",
      "#478061",
      "#87ac98",
      "#c8d9d0"
    ]
  }

  # In one ink.
  @mono ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
               d8888888888888888888888888888qq,
                "888888888888888888888888888888q,
                  "88888P""''''''""Y8888888888888q,
        __          ""                '"88888888888_
       q88q_                             "8888888888p
      q88888q_                             "888888888p
     )88888888P             .__,             O88888888p
    .88888888P          _pp888888qq,          O88888888,
    q88888888          p888888888888q          88888888p
    88888888P         q88888888888888p         )88888888
    88888888|        |8888888888888888,        |88888888
    88888888|        |8888888888888888|        |88888888
    88888888p         888888888888888P         q88888888
    d88888888,         Y888888888888P         .88888888P
    '88888888p          '"88888888"'          q88888888'
     )88888888q             ''''             d88888888"
      Y88888888q_                             "888888P
       Y888888888q_                             "888P
        "8888888888qq_                __          ""
         'Y888888888888qq__________pp888q_
           'Y88888888888888888888888888888q_
             '"88888888888888888888888888888b
                '"88888888888888888888888P"'
                    '""Y88888888888PP""'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
               d8888888888888888888888888888qq,
                "888888888888888888888888888888q,
                  "88888P""''''''""Y8888888888888q,
        __          ""                '"88888888888_
       q88q_                             "8888888888p
      q88888q_                             "888888888p
     )88888888P             .__,             O88888888p
    .88888888P          _pp888888qq,          O88888888,
    q88888888          p888888888888q          88888888p
    88888888P         q88888888888888p         )88888888
    88888888|        |8888888888888888,        |88888888
    88888888|        |8888888888888888|        |88888888
    88888888p         888888888888888P         q88888888
    d88888888,         Y888888888888P         .88888888P
    '88888888p          '"88888888"'          q88888888'
     )88888888q             ''''             d88888888"
      Y88888888q_                             "888888P
       Y888888888q_                             "888P
        "8888888888qq_                __          ""
         'Y888888888888qq__________pp888q_
           'Y88888888888888888888888888888q_
             '"88888888888888888888888888888b
                '"88888888888888888888888P"'
                    '""Y88888888888PP""'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
               00000000000000000000000000000000
                000000000000000000000000000000000
                  000000000000000000000000000000000
        00          00                00000000000000
       00000                             000000000000
      00000000                             00000000000
     0000000000             0000             0000000000
    0000000000          000000000000          0000000000
    000000000          00000000000000          000000000
    000000000         0000000000000000         000000000
    000000000        000000000000000000        000000000
    000000000        000000000000000000        000000000
    000000000         0000000000000000         000000000
    0000000000         00000000000000         0000000000
    0000000000          000000000000          0000000000
     0000000000             0000             0000000000
      00000000000                             00000000
       000000000000                             00000
        00000000000000                00          00
         000000000000000000000000000000000
           000000000000000000000000000000000
             00000000000000000000000000000000
                0000000000000000000000000000
                    00000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
