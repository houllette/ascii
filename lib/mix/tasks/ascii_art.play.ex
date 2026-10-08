defmodule Mix.Tasks.AsciiArt.Play do
  @shortdoc "Plays a piece in the terminal"
  @moduledoc """
  Plays a piece in the terminal, in colour, until you press `q` or Ctrl-C.

      mix ascii_art.play donut
      mix ascii_art.play night-coast --fps 10 --mode ansi256
      mix ascii_art.play typewriter --option "prefix=we make " --option phrases=tools,sites
      mix ascii_art.play MyApp.Pieces.Wave

  The piece is a slug or the name of a module implementing `AsciiArt.Piece`
  in this project or its dependencies.

  ## Options

    * `--fps N` - frames a second (default: the piece's own)
    * `--mono` - draw a coloured piece in one ink
    * `--paper` - dark ink on a light terminal: shaded pieces flip their ramps
    * `--mode truecolor|ansi256|mono` - how colour is written (default
      `truecolor`; use `ansi256` where 24-bit colour is not supported)
    * `--option key=value` - one of the piece's options; repeat for more. Keys
      must be the piece's own (see `AsciiArt.meta/1`); a list takes
      comma-separated values or JSON.
    * `--seconds S` - stop after S seconds instead of waiting for a key

  After the first frame only the cells that change are written, so it plays
  well over SSH or a serial console. The cursor is hidden while it plays and
  shown again below the picture, with the colours reset, when it stops.
  """
  use Mix.Task

  alias AsciiArt.{Player, Render.ANSI}

  @switches [
    fps: :integer,
    mono: :boolean,
    paper: :boolean,
    option: :keep,
    mode: :string,
    seconds: :float
  ]
  @modes %{"truecolor" => :truecolor, "ansi256" => :ansi256, "mono" => :mono}

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: @switches)

    name =
      case rest do
        [name] -> name
        _ -> Mix.raise(usage())
      end

    mode = mode(Keyword.get(opts, :mode, "truecolor"))
    Mix.Task.run("app.start")

    player_opts =
      [
        piece: piece(name),
        options: Map.new(Keyword.get_values(opts, :option), &option/1),
        paper: Keyword.get(opts, :paper, false),
        color: not Keyword.get(opts, :mono, false)
      ] ++ Keyword.take(opts, [:fps])

    {:ok, anim} =
      AsciiArt.prepare(player_opts[:piece], Keyword.delete(player_opts, :piece)) |> check()

    play(player_opts, mode, anim.meta.rows, Keyword.get(opts, :seconds))
  end

  # A slug, or a module of a loaded application named by the argument. The
  # name is compared with the modules that exist, so no atom is made from it.
  defp piece(name) do
    case AsciiArt.resolve(name) do
      {:ok, _} -> name
      {:error, :unknown_piece} -> find_module(name) || name
    end
  end

  defp find_module(name) do
    full = if String.starts_with?(name, "Elixir."), do: name, else: "Elixir." <> name

    Enum.find_value(Application.loaded_applications(), fn {app, _, _} ->
      app |> Application.spec(:modules) |> List.wrap() |> Enum.find(&(Atom.to_string(&1) == full))
    end)
  end

  # Frames go to a drawer, which keeps the last one and writes only what
  # changed since (see `AsciiArt.Render.ANSI.changes/3`): over SSH or a
  # serial line, a few cells in a hundred rather than the whole picture.
  defp play(player_opts, mode, rows, seconds) do
    out = Process.group_leader()
    IO.write(out, [ANSI.hide_cursor(), ANSI.clear()])
    drawer = spawn_link(fn -> draw(out, mode, nil) end)

    try do
      {:ok, player} = Player.start_link(Keyword.put(player_opts, :to, drawer))
      wait(seconds)
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
      {:ascii_art_frame, _ref, frame} ->
        IO.write(out, ANSI.changes(prev, frame, mode: mode))
        draw(out, mode, frame)

      {:stop, from} ->
        send(from, :stopped)
    end
  end

  defp wait(seconds) when is_number(seconds), do: Process.sleep(round(seconds * 1000))

  # Keys one at a time, if this is a terminal; q, Ctrl-C or end of input stop
  # it. Raw mode alone leaves Ctrl-C to the emulator's break menu, so the
  # terminal's signal keys are turned off while it plays, and Ctrl-C arrives
  # as a key like any other.
  defp wait(nil) do
    case :shell.start_interactive({:noshell, :raw}) do
      :ok ->
        tty = tty()
        saved = tty && stty(tty, ["-g"])

        try do
          if saved, do: stty(tty, ["-isig"])
          read_keys()
        after
          if saved, do: stty(tty, [String.trim(saved)])
        end

      {:error, _} ->
        IO.read(:eof)
    end
  end

  # The VM's terminal, by device: programs it starts have no controlling
  # terminal, so /dev/tty is not theirs to open.
  defp tty do
    with {name, 0} <- System.cmd("ps", ["-o", "tty=", "-p", System.pid()], stderr_to_stdout: true),
         name = String.trim(name),
         true <- name =~ ~r{^[A-Za-z0-9/]+$} and name not in ["?", "??"] do
      "/dev/" <> name
    else
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  # stty on that device, given as an argument rather than spliced into the command.
  defp stty(tty, args) do
    case System.cmd("sh", ["-c", ~s(stty "$@" < "$0"), tty | args], stderr_to_stdout: true) do
      {out, 0} -> out
      _ -> nil
    end
  end

  defp read_keys do
    case IO.getn("", 1) do
      key when key in ["q", "Q", <<3>>, <<4>>] -> :ok
      :eof -> :ok
      {:error, _} -> :ok
      _ -> read_keys()
    end
  end

  defp option(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] -> {key, value}
      _ -> Mix.raise("--option takes key=value, got #{inspect(pair)}")
    end
  end

  defp mode(name) do
    case Map.fetch(@modes, name) do
      {:ok, mode} -> mode
      :error -> Mix.raise("--mode must be truecolor, ansi256 or mono, got #{inspect(name)}")
    end
  end

  defp check({:ok, anim}), do: {:ok, anim}

  defp check({:error, :unknown_piece}),
    do:
      Mix.raise(
        "unknown piece: give a slug (see AsciiArt.pieces/0) or a module implementing AsciiArt.Piece"
      )

  defp check({:error, {:invalid_option, :fps}}), do: Mix.raise("invalid --fps")

  defp check({:error, {:invalid_option, key}}),
    do:
      Mix.raise(
        "invalid option #{inspect(key)}: options must be the piece's own, with values of the same kind"
      )

  defp usage,
    do:
      "usage: mix ascii_art.play <piece> [--fps N] [--mono] [--paper] [--mode M] [--option key=value]"
end
