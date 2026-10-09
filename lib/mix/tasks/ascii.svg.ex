defmodule Mix.Tasks.Ascii.Svg do
  @shortdoc "Writes a frame of a piece as an SVG"
  @moduledoc """
  Writes one frame of a piece as an SVG picture (`Ascii.Render.SVG`),
  for a README, an email or a social preview.

      mix ascii.svg night-coast
      mix ascii.svg big-text --option text=hello --ink ff5f6d,ffc371 --output hello.svg
      mix ascii.svg gauge --option value=72 --parts --background 0d1117 --foreground c9d1d9

  The piece is a slug or a module, as for `mix ascii.play`, and takes
  the same `--option`, `--mono`, `--ink`, `--gradient`, `--parts`, `--part`
  and `--paper`. It is labelled for screen readers with what it shows
  (`Ascii.describe/1`).

  ## Options

    * `--t S` - the time to draw, in seconds (default 0: frame 0)
    * `--output FILE` - where to write it (default `<piece>.svg`; `-` for
      standard output)
    * `--font-size PX` - the font's size in pixels (default 14)
    * `--background COLOUR`, `--foreground COLOUR` - behind the picture,
      and for its uncoloured text (defaults: the piece's ground, and the
      colour of the text around it)
  """
  use Mix.Task

  alias Ascii.Render.SVG
  alias Mix.Ascii.Args

  # Read at run time: the shared switches are not a compile-time dependency.
  defp switches,
    do:
      Args.switches() ++
        [
          t: :float,
          output: :string,
          font_size: :integer,
          background: :string,
          foreground: :string
        ]

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: switches())

    name =
      case rest do
        [name] -> name
        _ -> Mix.raise("usage: mix ascii.svg <piece> [--t S] [--output FILE] [options]")
      end

    Mix.Task.run("app.start")
    {piece, new_opts} = Args.piece!(name, opts)
    anim = Ascii.new!(piece, new_opts)
    {frame, _anim} = Ascii.frame(anim, Keyword.get(opts, :t, 0.0))

    svg =
      SVG.render(
        frame,
        [title: Ascii.describe(anim)] ++
          Keyword.take(opts, [:font_size]) ++
          colour(opts, :background) ++ colour(opts, :foreground)
      )

    case Keyword.get(opts, :output, default_output(name)) do
      "-" ->
        IO.write(svg)

      path ->
        File.write!(path, svg)
        Mix.shell().info("wrote #{path}: #{frame.cols}×#{frame.rows} cells")
    end
  end

  defp default_output(name),
    do: (name |> String.split(".") |> List.last() |> Macro.underscore()) <> ".svg"

  defp colour(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, given} ->
        [{key, Ascii.Ink.color(given) || Mix.raise("--#{key} takes a colour, rrggbb")}]

      :error ->
        []
    end
  end
end
