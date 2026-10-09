defmodule Mix.Tasks.Ascii.Play do
  @shortdoc "Plays a piece in the terminal"
  @moduledoc """
  Plays a piece in the terminal, in colour, until you press `q` or Ctrl-C.

      mix ascii.play donut
      mix ascii.play night-coast --fps 10 --mode ansi256
      mix ascii.play typewriter --option "prefix=we make " --option phrases=tools,sites
      mix ascii.play big-text --ink ff5f6d,ffc371
      mix ascii.play boot-log --parts
      mix ascii.play file-tree --part folder=58a6ff --part file.md=d29922
      mix ascii.play MyApp.Pieces.Wave

  The piece is a slug or the name of a module implementing `Ascii.Piece`
  in this project or its dependencies.

  ## Options

    * `--fps N` - frames a second (default: the piece's own)
    * `--mono` - draw a coloured piece in one ink
    * `--ink COLOURS` - the colour of a piece drawn in one ink: `rrggbb`
      (a leading `#` is optional, but quote it in a shell), or several,
      comma-separated, for a gradient (see `Ascii.Ink`)
    * `--gradient horizontal|vertical|diagonal` - which way several inks run
      (default `horizontal`)
    * `--parts` - colour the parts of a piece that knows them (see
      `Ascii.Parts`) as it suggests
    * `--part name=COLOUR` - a colour for one part, over `--parts` if given;
      repeat for more
    * `--paper` - dark ink on a light terminal: shaded pieces flip their ramps
    * `--mode truecolor|ansi256|mono` - how colour is written (default
      `truecolor`; use `ansi256` where 24-bit colour is not supported)
    * `--option key=value` - one of the piece's options; repeat for more. Keys
      must be the piece's own (see `Ascii.meta/1`); a list takes
      comma-separated values or JSON.
    * `--seconds S` - stop after S seconds instead of waiting for a key
    * `--interactive` - keys go to a piece that can be used (see
      `Ascii.handle_event/2`): arrows, enter, space, tab, typing. Ctrl-C
      stops it, as `q` would be a key for the piece.

        mix ascii.play file-tree --option walk=false --interactive
        mix ascii.play calendar --option date=2026-10-08 --interactive

  After the first frame only the cells that change are written, so it plays
  well over SSH or a serial console. The cursor is hidden while it plays and
  shown again below the picture, with the colours reset, when it stops.
  """
  use Mix.Task

  alias Ascii.{Player, Render.ANSI}
  alias Mix.Ascii.{Args, Terminal}

  @modes %{"truecolor" => :truecolor, "ansi256" => :ansi256, "mono" => :mono}

  # Read at run time: the shared switches are not a compile-time dependency.
  defp switches,
    do:
      Args.switches() ++
        [
          fps: :integer,
          mode: :string,
          seconds: :float,
          interactive: :boolean
        ]

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: switches())

    name =
      case rest do
        [name] -> name
        _ -> Mix.raise(usage())
      end

    mode = mode(Keyword.get(opts, :mode, "truecolor"))
    Mix.Task.run("app.start")

    {piece, new_opts} = Args.piece!(name, opts)
    {:ok, anim} = Ascii.prepare(piece, new_opts)
    player_opts = [piece: piece] ++ new_opts

    play(player_opts, mode, anim.meta.rows, Keyword.get(opts, :seconds), opts[:interactive])
  end

  defp play(player_opts, mode, rows, seconds, interactive?) do
    out = Process.group_leader()
    IO.write(out, [ANSI.hide_cursor(), ANSI.clear()])
    drawer = spawn_link(fn -> draw(out, mode, nil) end)

    try do
      {:ok, player} = Player.start_link(Keyword.put(player_opts, :to, drawer))
      on_key = if interactive?, do: &Player.handle_event(player, {:key, &1})
      Terminal.wait(seconds, on_key)
      Player.stop(player)
      send(drawer, {:stop, self()})

      receive do
        :stopped -> :ok
      end
    after
      IO.write(out, [ANSI.reset(), ANSI.move(rows + 1, 1), ANSI.show_cursor()])
    end
  end

  defp draw(out, mode, prev) do
    receive do
      {:ascii_frame, _ref, frame} ->
        IO.write(out, ANSI.changes(prev, frame, mode: mode))
        draw(out, mode, frame)

      {:stop, from} ->
        send(from, :stopped)
    end
  end

  defp mode(name) do
    case Map.fetch(@modes, name) do
      {:ok, mode} -> mode
      :error -> Mix.raise("--mode must be truecolor, ansi256 or mono, got #{inspect(name)}")
    end
  end

  defp usage,
    do:
      "usage: mix ascii.play <piece> [--fps N] [--mono] [--ink C,...] [--gradient G] " <>
        "[--parts] [--part name=C] [--paper] [--mode M] [--option key=value] [--interactive]"
end
