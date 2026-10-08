defmodule AsciiArt.Piece do
  @moduledoc """
  The piece contract, upstream's in Elixir.

  Upstream, a piece's default function takes the options, precomputes, and
  returns a closure `frame(t, env)`. Here `init/1` is the outer function: it
  receives every option (the defaults merged with what was asked for) and
  returns a state. `frame/3` is the closure: given the state, the play time
  `t` in seconds and the `AsciiArt.Env`, it returns the picture as iodata,
  the colours, and the next state.

  The picture is `rows` lines of exactly `cols` characters joined by `\\n`.
  Colours are `nil` unless the piece has a palette and `env.color?` is set;
  then they are a binary of `cols * rows` palette indices, row by row.

  State is threaded because upstream closures keep state between frames: a
  simulation that steps by how far `t` moved, a cache of the last minute
  drawn. A piece behaves exactly as its upstream closure does when called with
  the same sequence of `t`, including `t` going backwards.

  ## Example

      defmodule MySpinner do
        @behaviour AsciiArt.Piece

        @meta %AsciiArt.Meta{
          name: "spinner",
          category: :ui,
          note: "a line turning while something loads",
          cols: 10,
          rows: 1,
          fps: 6
        }

        @impl true
        def meta, do: @meta

        @impl true
        def init(_options), do: nil

        @impl true
        def frame(state, t, _env) do
          {[Enum.at(~w(| / - \\\\), rem(floor(t * 3), 4)), " loading "], nil, state}
        end
      end
  """

  @doc "The piece's `AsciiArt.Meta`."
  @callback meta() :: AsciiArt.Meta.t()

  @doc "Precomputes from every option, merged with the defaults."
  @callback init(options :: map()) :: state :: term()

  @doc "The picture at `t` seconds, its colours, and the next state."
  @callback frame(state :: term(), t :: float(), env :: AsciiArt.Env.t()) ::
              {iodata(), colors :: binary() | nil, state :: term()}

  @doc """
  The frame's size for these options, `{cols, rows}`, for a piece whose size
  follows its options (a width to fit a terminal, a row a series). Without
  it, every frame is the meta's size.
  """
  @callback size(options :: map()) :: {cols :: pos_integer(), rows :: pos_integer()}

  @doc """
  The state for new options while playing (see `AsciiArt.put_options/2`),
  keeping what it can of `state`: a needle swinging to a new reading, a
  scroll carrying on. Without it, `init/1` starts afresh.
  """
  @callback update(state :: term(), options :: map()) :: state :: term()

  @optional_callbacks size: 1, update: 2
end
