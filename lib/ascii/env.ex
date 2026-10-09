defmodule Ascii.Env do
  @moduledoc """
  What a frame is drawn for, upstream's `env` plus the size and the clock.

  - `paper`: ink is dark on a light ground, so shaded pieces flip their ramp.
  - `color?`: colours are wanted. A coloured piece then returns a palette
    index for every cell; otherwise it draws the one-ink version and returns
    `nil` colours.
  - `now`: the wall clock for `clock: true` pieces, as a `DateTime` whose
    offset gives the local time. `nil` reads the system clock. Tests pin it.
  """

  @type t :: %__MODULE__{
          cols: pos_integer(),
          rows: pos_integer(),
          paper: boolean(),
          color?: boolean(),
          now: DateTime.t() | nil
        }

  defstruct cols: 80, rows: 24, paper: false, color?: false, now: nil
end
