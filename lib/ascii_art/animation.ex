defmodule AsciiArt.Animation do
  @moduledoc """
  A piece being played: its module and options, how it is drawn, and its
  state so far. Made by `AsciiArt.new/2` and advanced by `AsciiArt.frame/3`.
  """

  alias AsciiArt.{Env, Frame, Ink, Meta}

  @type t :: %__MODULE__{
          module: module(),
          meta: Meta.t(),
          options: map(),
          fps: 0..60,
          cols: pos_integer(),
          rows: pos_integer(),
          paper: boolean(),
          color?: boolean(),
          ink: Ink.t() | nil,
          state: term()
        }

  @enforce_keys [:module, :meta, :options, :fps, :cols, :rows, :paper, :color?, :state]
  defstruct [:module, :meta, :options, :fps, :cols, :rows, :paper, :color?, :state, ink: nil]

  @doc false
  @spec new(module :: module(), meta :: Meta.t(), options :: map(), keyword()) :: t()
  def new(module, meta, options, opts) do
    color? = Keyword.get(opts, :color, true) and Meta.colored?(meta)
    {cols, rows} = size(module, meta, options)

    %__MODULE__{
      module: module,
      meta: meta,
      options: options,
      fps: Keyword.get(opts, :fps, meta.fps),
      cols: cols,
      rows: rows,
      paper: paper(meta, color?, Keyword.get(opts, :paper, false)),
      color?: color?,
      # A piece drawn in its own colours has no use for an ink.
      ink: if(not color?, do: Ink.fit(Keyword.get(opts, :ink), cols, rows, meta.cell)),
      state: nil
    }
  end

  @doc false
  # Runs the piece's init/1: until then the animation cannot draw.
  @spec setup(anim :: t()) :: t()
  def setup(%__MODULE__{module: module, options: options} = anim),
    do: %{anim | state: module.init(options)}

  @doc false
  # New options, already cast: the piece carries its state over if it can,
  # else starts afresh; its size follows.
  @spec put_options(anim :: t(), options :: map()) :: t()
  def put_options(%__MODULE__{module: module, meta: meta} = anim, options) do
    {cols, rows} = size(module, meta, options)

    state =
      if function_exported?(module, :update, 2),
        do: module.update(anim.state, options),
        else: module.init(options)

    ink = Ink.fit(anim.ink, cols, rows, meta.cell)
    %{anim | options: options, cols: cols, rows: rows, ink: ink, state: state}
  end

  defp size(module, meta, options) do
    if function_exported?(module, :size, 1),
      do: module.size(options),
      else: {meta.cols, meta.rows}
  end

  # As upstream's mount: a coloured piece drawn in colour over its own ground
  # takes paper from how light that ground is.
  defp paper(%Meta{ground: ground}, true, _asked) when is_binary(ground), do: light?(ground)
  defp paper(_meta, _color?, asked), do: asked == true

  defp light?(<<"#", hex::binary-size(6)>>) do
    <<r, g, b>> = Base.decode16!(hex, case: :mixed)
    0.2126 * r + 0.7152 * g + 0.0722 * b >= 128
  end

  @doc false
  # A looping piece's cycle as frames to draw: their count, the rate to show
  # them at (the animation's, or as near as a whole number of frames
  # allows), and whether the period holds as measured, with these very
  # options and this rate. nil for a piece that does not loop, or a still.
  @spec cycle(anim :: t()) :: {pos_integer(), number(), boolean()} | nil
  def cycle(%__MODULE__{meta: %Meta{loop: seconds}, fps: fps} = anim)
      when is_number(seconds) and fps > 0 do
    n = round(seconds * fps)
    # When the period is a whole number of frames, the frames fall where they
    # were measured: at i / fps, not at i * seconds / n, which can round apart.
    rate = if abs(n - seconds * fps) < 1.0e-6, do: fps, else: n / seconds
    {n, rate, anim.options == anim.meta.options and fps == anim.meta.fps}
  end

  def cycle(%__MODULE__{}), do: nil

  @doc false
  # The piece's frame, in the animation's ink if it has one: laid over the
  # picture, which the piece draws as ever.
  @spec frame(anim :: t(), t :: number(), now :: DateTime.t() | nil) :: {Frame.t(), t()}
  def frame(%__MODULE__{meta: meta, cols: cols, rows: rows} = anim, t, now) do
    t = t * 1.0
    env = %Env{cols: cols, rows: rows, paper: anim.paper, color?: anim.color?, now: now}
    {io, colors, state} = anim.module.frame(anim.state, t, env)
    text = IO.iodata_to_binary(io)

    frame = %Frame{
      text: text,
      lines: String.split(text, "\n"),
      colors: colors,
      palette: if(anim.color?, do: meta.palette),
      ground: meta.ground,
      cols: cols,
      rows: rows,
      cell: meta.cell,
      t: t
    }

    {paint(anim, frame), %{anim | state: state}}
  end

  @doc false
  # A frame of the piece's in the animation's ink, its parts read off it if
  # the ink colours any.
  @spec paint(anim :: t(), frame :: Frame.t()) :: Frame.t()
  def paint(%__MODULE__{ink: nil}, frame), do: frame

  def paint(%__MODULE__{ink: ink, module: module, options: options}, %Frame{colors: nil} = frame) do
    parts =
      if Ink.parts?(ink) and function_exported?(module, :parts, 2),
        do: module.parts(frame, options)

    Ink.tint(frame, ink, parts)
  end

  def paint(_anim, frame), do: frame
end
