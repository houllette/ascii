defmodule AsciiArt do
  @moduledoc """
  Animated ASCII art, ported from [ascii.rest](https://ascii.rest) by
  [@bas3line](https://github.com/bas3line).

  Every piece is a function of time: give it `t` in seconds and it draws a
  frame, exactly `rows` lines of `cols` characters, and for coloured pieces a
  palette index for every cell. Frames are plain data (`AsciiArt.Frame`), so
  they can go to a terminal (`AsciiArt.Render.ANSI`, `AsciiArt.Player`), a
  LiveView (`AsciiArt.Phoenix.Components`), or a framebuffer on a device.

      iex> AsciiArt.pieces() |> Enum.member?("donut")
      true

      AsciiArt.render!("donut", 1.5) |> IO.puts()

      {:ok, anim} = AsciiArt.new("night-coast", fps: 10)
      {frame, anim} = AsciiArt.frame(anim, 0.1)

  Anywhere a piece is expected, pass its slug (the upstream file name, such as
  `"night-coast"`) or its module (`AsciiArt.Pieces.NightCoast`).
  """

  alias AsciiArt.{Animation, Frame, Meta, Options, Registry}

  @upstream_commit "fcb644403bfc25af0002e415d1006dd10b99ca34"

  @typedoc "A piece: its slug or its module."
  @type piece :: String.t() | module()

  @typedoc "Why a piece could not be played."
  @type error ::
          {:error, :unknown_piece}
          | {:error, {:invalid_option, term()}}

  @doc "The upstream commit this port follows."
  @spec upstream_commit() :: String.t()
  def upstream_commit, do: @upstream_commit

  @doc """
  Every piece's slug, sorted. `category:` keeps one category.

      iex> "night-coast" in AsciiArt.pieces(category: :scenes)
      true
  """
  @spec pieces(opts :: [category: Meta.category()]) :: [String.t()]
  def pieces(opts \\ []) do
    case Keyword.fetch(opts, :category) do
      {:ok, category} ->
        for {slug, mod} <- Registry.all(), mod.meta().category == category, do: slug

      :error ->
        Registry.slugs()
    end
  end

  @doc "A piece's `AsciiArt.Meta`."
  @spec meta(piece :: piece()) :: {:ok, Meta.t()} | {:error, :unknown_piece}
  def meta(piece) do
    with {:ok, mod} <- resolve(piece), do: {:ok, mod.meta()}
  end

  @doc "Like `meta/1`, raising for an unknown piece."
  @spec meta!(piece :: piece()) :: Meta.t()
  def meta!(piece), do: unwrap!(meta(piece))

  @doc """
  The module for a piece, given its slug or a module that implements
  `AsciiArt.Piece` (registered or not).
  """
  @spec resolve(piece :: piece()) :: {:ok, module()} | {:error, :unknown_piece}
  def resolve(slug) when is_binary(slug) do
    case Registry.fetch(slug) do
      {:ok, mod} -> {:ok, mod}
      :error -> {:error, :unknown_piece}
    end
  end

  def resolve(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :meta, 0) and
         function_exported?(mod, :init, 1) and function_exported?(mod, :frame, 3),
       do: {:ok, mod},
       else: {:error, :unknown_piece}
  end

  def resolve(_piece), do: {:error, :unknown_piece}

  @doc """
  Starts playing a piece.

  ## Options

    * `:options` - the piece's own options, a map or keyword list, checked
      against its defaults (see `AsciiArt.Options`).
    * `:fps` - frames a second for `stream/2` and players, 0 to 60. Defaults
      to the piece's own.
    * `:paper` - the picture is dark ink on a light ground, so shaded pieces
      flip their ramps. Defaults to `false`. A coloured piece drawn in colour
      over its own `ground` takes this from the ground instead, as upstream.
    * `:color` - draw coloured pieces in colour (`true`, the default) or as
      text in one ink.
  """
  @spec new(piece :: piece(), opts :: keyword()) :: {:ok, Animation.t()} | error()
  def new(piece, opts \\ []) do
    with {:ok, anim} <- prepare(piece, opts), do: {:ok, Animation.setup(anim)}
  end

  # Everything new/2 checks, but the piece not yet set up: its init/1 can
  # take a second, which AsciiArt.Player spends after it has started.
  @doc false
  @spec prepare(piece :: piece(), opts :: keyword()) :: {:ok, Animation.t()} | error()
  def prepare(piece, opts) do
    with {:ok, mod} <- resolve(piece),
         meta = mod.meta(),
         {:ok, options} <- Options.cast(meta, Keyword.get(opts, :options, %{})),
         {:ok, fps} <- fps(Keyword.get(opts, :fps, meta.fps)) do
      {:ok, Animation.new(mod, meta, options, Keyword.put(opts, :fps, fps))}
    end
  end

  @doc "Like `new/2`, raising on an error."
  @spec new!(piece :: piece(), opts :: keyword()) :: Animation.t()
  def new!(piece, opts \\ []), do: unwrap!(new(piece, opts))

  @doc """
  New options for a playing animation, for live data in a dashboard or a
  terminal UI: a reading for a gauge, the latest samples for a sparkline.

  `options` are checked as `new/2` checks them and merged over the
  animation's own, so only what changes need be given. A piece that can
  carries its state over (a gauge's needle swings from where it was to the
  new reading); any other starts afresh with the new options. A piece whose
  size follows its options takes its new size.

      anim = AsciiArt.new!("gauge", options: %{value: 40})
      anim = AsciiArt.put_options!(anim, value: 72)
  """
  @spec put_options(anim :: Animation.t(), options :: map() | keyword()) ::
          {:ok, Animation.t()} | error()
  def put_options(%Animation{} = anim, options) do
    with {:ok, options} <- Options.cast(anim.meta, options, anim.options),
         do: {:ok, Animation.put_options(anim, options)}
  end

  @doc "Like `put_options/2`, raising on an error."
  @spec put_options!(anim :: Animation.t(), options :: map() | keyword()) :: Animation.t()
  def put_options!(anim, options), do: unwrap!(put_options(anim, options))

  defp fps(fps) when is_number(fps), do: {:ok, fps |> max(0) |> min(60) |> round()}

  defp fps(fps) when is_binary(fps) do
    case Integer.parse(fps) do
      {n, ""} -> fps(n)
      _ -> {:error, {:invalid_option, :fps}}
    end
  end

  defp fps(_fps), do: {:error, {:invalid_option, :fps}}

  @doc """
  The frame at `t` seconds of play time, and the animation to draw the next
  one from. Pieces with state (simulations, mostly) step by how far `t` moved
  since the last frame, so play `t` forward.

  `opts` may give `:now`, a `DateTime` for pieces that read the clock.
  """
  @spec frame(anim :: Animation.t(), t :: number(), opts :: [now: DateTime.t()]) ::
          {Frame.t(), Animation.t()}
  def frame(%Animation{} = anim, t, opts \\ []),
    do: Animation.frame(anim, t, Keyword.get(opts, :now))

  @doc """
  One frame of a piece as text, from a fresh start. Takes the options of
  `new/2`, and `:now`.

      iex> {:ok, text} = AsciiArt.render("spinners")
      iex> text |> String.split("\\n") |> length()
      13
  """
  @spec render(piece :: piece(), t :: number(), opts :: keyword()) :: {:ok, String.t()} | error()
  def render(piece, t \\ 0.0, opts \\ []) do
    with {:ok, anim} <- new(piece, opts) do
      {frame, _anim} = frame(anim, t, Keyword.take(opts, [:now]))
      {:ok, frame.text}
    end
  end

  @doc """
  Frame 0 of a piece: what a page shows before it plays, and what a reader
  who prefers reduced motion sees. Takes the options of `new/2`, and `:now`.

  With the piece's default options it is drawn once and kept for the life of
  the VM, so later calls have it at once: a scene takes up to a second to set
  up, and a page that shows stills, or a player's first render, pays for that
  once rather than on every request. A piece that reads the clock is drawn
  every time, as are other options.

      iex> {:ok, frame} = AsciiArt.still("elixir")
      iex> {frame.cols, frame.rows, frame.t}
      {38, 28, 0.0}
  """
  @spec still(piece :: piece(), opts :: keyword()) :: {:ok, Frame.t()} | error()
  def still(piece, opts \\ []) do
    with {:ok, anim} <- prepare(piece, opts) do
      if anim.options == anim.meta.options and not anim.meta.clock do
        key = {__MODULE__, :still, anim.module, anim.paper, anim.color?}

        case :persistent_term.get(key, nil) do
          nil ->
            frame = draw_still(anim, opts)
            :persistent_term.put(key, frame)
            {:ok, frame}

          frame ->
            {:ok, frame}
        end
      else
        {:ok, draw_still(anim, opts)}
      end
    end
  end

  defp draw_still(anim, opts) do
    {frame, _anim} = anim |> Animation.setup() |> Animation.frame(0.0, Keyword.get(opts, :now))
    frame
  end

  @doc "Like `render/3`, raising on an error."
  @spec render!(piece :: piece(), t :: number(), opts :: keyword()) :: String.t()
  def render!(piece, t \\ 0.0, opts \\ []), do: unwrap!(render(piece, t, opts))

  @doc """
  The piece's frames as a lazy stream, one every `1/fps` seconds from 0. A
  still (fps 0) gives one frame. Takes the options of `new/2`.

      iex> {:ok, frames} = AsciiArt.stream("spinners")
      iex> frames |> Enum.take(3) |> Enum.map(& &1.t)
      [0.0, 0.08333333333333333, 0.16666666666666666]
  """
  @spec stream(piece :: piece(), opts :: keyword()) :: {:ok, Enumerable.t(Frame.t())} | error()
  def stream(piece, opts \\ []) do
    with {:ok, anim} <- new(piece, opts) do
      now = Keyword.get(opts, :now)
      still? = anim.fps == 0

      frames =
        Stream.unfold({anim, 0}, fn
          {_anim, 1} when still? ->
            nil

          {anim, i} ->
            t = if anim.fps == 0, do: 0.0, else: i / anim.fps
            {frame, anim} = Animation.frame(anim, t, now)
            {frame, {anim, i + 1}}
        end)

      {:ok, frames}
    end
  end

  @doc "Like `stream/2`, raising on an error."
  @spec stream!(piece :: piece(), opts :: keyword()) :: Enumerable.t(Frame.t())
  def stream!(piece, opts \\ []), do: unwrap!(stream(piece, opts))

  @doc """
  One cycle of a piece that closes a loop (see `AsciiArt.Meta`): its frames
  from `t = 0`, evenly spaced through the period, and the rate to show them
  at, the animation's own or as near as a whole number of frames allows.
  Played over and over, they are the piece, so a player can draw a loop once
  and repeat it rather than draw every frame anew.

  The period is measured with the piece's default options and frame rate.
  With others, which can change it (a longer text takes longer to scroll),
  the frames of a second cycle are drawn too, and the loop stands only if
  they match the first. `:error` means the piece is to be drawn frame by
  frame.

      iex> {:ok, frames, fps} = AsciiArt.new!("elixir") |> AsciiArt.loop()
      iex> {length(frames), fps}
      {150, 30}
  """
  @spec loop(anim :: Animation.t()) :: {:ok, [Frame.t()], fps :: number()} | :error
  def loop(%Animation{} = anim) do
    case Animation.cycle(anim) do
      {n, rate, measured?} ->
        count = if measured?, do: n, else: 2 * n

        {frames, _anim} =
          Enum.map_reduce(0..(count - 1), anim, fn i, anim ->
            Animation.frame(anim, i / rate, nil)
          end)

        {cycle, next} = Enum.split(frames, n)
        if measured? or pictures(cycle) == pictures(next), do: {:ok, cycle, rate}, else: :error

      nil ->
        :error
    end
  end

  defp pictures(frames), do: Enum.map(frames, &{&1.text, &1.colors})

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "ascii_art: #{inspect(reason)}")
end
