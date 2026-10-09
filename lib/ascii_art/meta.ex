defmodule AsciiArt.Meta do
  @moduledoc """
  What a piece is: upstream's `meta`, field for field.

  `name` is the lowercase display name, `note` one lowercase line saying what
  you see. Every frame is exactly `rows` lines of `cols` characters, played at
  `fps` frames a second (0 for a still). `options` holds the default of every
  option, keyed by atom. `clock` is true when the picture reads the real time.
  A coloured piece has a `palette` of `#rrggbb` colours, which its colour
  indices point into, and scenes a `ground` behind them. `cell` is a cell's
  height in cell widths on a canvas: 2, the shape of a character, or 1.

  `bounds` is this port's own addition: the range each numeric option is
  clamped to when it comes from outside (see `AsciiArt.Options`); for an
  option that holds lists or maps, a range for every number within it, or a
  map of ranges by key. So is
  `loop`: for a piece that closes a loop, the seconds after which its
  frames come round again exactly, with its default options and frame rate
  (measured by `tools/loops.exs`, held by a test). `AsciiArt.loop/1` gives
  the frames of one cycle, which a player can repeat rather than draw anew.
  And `shapes`: for an option whose default cannot show what it takes (an
  empty list that takes numbers, a series that may carry its own values), an
  example of what it takes, which `AsciiArt.Options` checks against instead.
  And `parts`: for a piece in one ink that labels its frames' cells (see
  `AsciiArt.Parts`), the names of its parts, in the order they read best,
  each with the colour it suggests for it, or `nil`.

  `cols` and `rows` are the size with the default options. A piece whose
  size follows its options (see `c:AsciiArt.Piece.size/1`) can be another
  size; a frame's own `cols` and `rows` always say.
  """

  @categories [
    :scenes,
    :shapes,
    :space,
    :physics,
    :nature,
    :creatures,
    :objects,
    :generative,
    :effects,
    :ui,
    :data,
    :type,
    :logos,
    :distros
  ]

  @typedoc "One of the fourteen upstream categories."
  @type category ::
          :scenes
          | :shapes
          | :space
          | :physics
          | :nature
          | :creatures
          | :objects
          | :generative
          | :effects
          | :ui
          | :data
          | :type
          | :logos
          | :distros

  @type t :: %__MODULE__{
          name: String.t(),
          category: category(),
          note: String.t(),
          cols: pos_integer(),
          rows: pos_integer(),
          fps: 0..60,
          options: %{optional(atom()) => term()},
          clock: boolean(),
          palette: [String.t()] | nil,
          ground: String.t() | nil,
          cell: 1 | 2,
          bounds: %{optional(atom()) => bound()},
          shapes: %{optional(atom()) => term()},
          parts: [{String.t(), String.t() | nil}],
          loop: number() | nil
        }

  @typedoc "A range, or ranges by key for the maps an option holds."
  @type bound :: {number(), number()} | %{optional(atom()) => bound()}

  @enforce_keys [:name, :category, :note, :cols, :rows, :fps]
  defstruct [
    :name,
    :category,
    :note,
    :cols,
    :rows,
    :fps,
    options: %{},
    clock: false,
    palette: nil,
    ground: nil,
    cell: 2,
    bounds: %{},
    shapes: %{},
    parts: [],
    loop: nil
  ]

  @doc "The fourteen categories, in upstream's order."
  @spec categories() :: [category()]
  def categories, do: @categories

  @doc "Whether the piece draws in colour."
  @spec colored?(meta :: t()) :: boolean()
  def colored?(%__MODULE__{palette: palette}), do: palette != nil
end
