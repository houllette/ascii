defmodule Mix.Tasks.Ascii.Top do
  @shortdoc "Watches this BEAM in the terminal, htop-style"
  @moduledoc """
  This VM in the terminal, htop-style, until you press `q` or Ctrl-C: its
  schedulers as cores, its memory, its run queue as the load, its busiest
  processes, and the last two minutes of memory, processes and run queue.

      mix ascii.top
      mix ascii.top --interval 2 --mode ansi256

  Run in your project, it starts your application first, so what it
  watches is your app at work. It is made of the pieces themselves: a
  `cpu-meters` and a `sparkline` fed by `Ascii.BEAM`, in panels put
  together by `Ascii.Compose`, side by side when the terminal is wide
  enough, and only the cells that change are written.

  ## Options

    * `--interval S` - seconds between samples (default 1)
    * `--mode truecolor|ansi256|mono` - how colour is written (default
      `truecolor`)
    * `--no-parts` - in the terminal's own colours, not the pieces'
      suggested ones
    * `--paper` - colours for a light terminal
    * `--seconds S` - stop after S seconds instead of waiting for a key
  """
  use Mix.Task

  alias Ascii.{BEAM, Compose, Render.ANSI}
  alias Mix.Ascii.Terminal

  @switches [interval: :float, mode: :string, parts: :boolean, paper: :boolean, seconds: :float]
  @modes %{"truecolor" => :truecolor, "ansi256" => :ansi256, "mono" => :mono}
  @fps 10

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)

    mode =
      case Map.fetch(@modes, Keyword.get(opts, :mode, "truecolor")) do
        {:ok, mode} -> mode
        :error -> Mix.raise("--mode must be truecolor, ansi256 or mono")
      end

    Mix.Task.run("app.start")
    out = Process.group_leader()
    interval = max(Keyword.get(opts, :interval, 1.0), 0.1)

    look = [parts: Keyword.get(opts, :parts, true), paper: Keyword.get(opts, :paper, false)]
    IO.write(out, [ANSI.hide_cursor(), ANSI.clear()])
    drawer = spawn_link(fn -> draw(start(look, interval), out, mode) end)
    sampler = spawn_link(fn -> sample(drawer, nil, round(interval * 1000)) end)

    try do
      Terminal.wait(Keyword.get(opts, :seconds), nil)
    after
      Process.unlink(sampler)
      Process.exit(sampler, :kill)
      send(drawer, {:stop, self()})

      receive do
        {:stopped, rows} ->
          IO.write(out, [ANSI.reset(), ANSI.move(rows + 1, 1), ANSI.show_cursor()])
      after
        1000 -> IO.write(out, [ANSI.reset(), ANSI.show_cursor()])
      end
    end
  end

  # A sample every `ms`, each from the last, in a process of its own: it
  # holds the scheduler_wall_time flag for as long as it lives. The first
  # only starts the measuring: it has no use or busiest processes yet.
  defp sample(drawer, prev, ms) do
    s = BEAM.sample(prev)
    if prev, do: send(drawer, {:sample, s})
    Process.sleep(ms)
    sample(drawer, s, ms)
  end

  defp start(look, interval) do
    meters = Ascii.new!("cpu-meters", look)
    history = Ascii.new!("sparkline", [options: %{cols: 66, rate: 1 / interval}] ++ look)
    border = if look[:parts], do: "#8b949e"

    %{
      meters: meters,
      history: history,
      border: border,
      interval: interval,
      t: 0.0,
      prev: nil,
      started: false
    }
  end

  # Draws @fps times a second, whatever has changed since the last frame.
  defp draw(state, out, mode) do
    receive do
      {:sample, s} ->
        meters = Ascii.put_options!(state.meters, BEAM.cpu_meters(s))
        options = Map.put(BEAM.sparkline(s, rate: 1 / state.interval), :cols, 66)
        history = Ascii.put_options!(state.history, options)
        draw(%{state | meters: meters, history: history, started: true}, out, mode)

      {:stop, from} ->
        send(from, {:stopped, if(state.prev, do: state.prev.rows, else: 0)})
    after
      round(1000 / @fps) ->
        state = if state.started, do: tick(state, out, mode), else: state
        draw(state, out, mode)
    end
  end

  defp tick(state, out, mode) do
    t = state.t + 1 / @fps
    {meters, m} = Ascii.frame(state.meters, t)
    {history, h} = Ascii.frame(state.history, t)
    frame = layout(meters, history, size(), state.border)

    # At a new size, from a clear screen: what the last drew past it would stay.
    prev =
      if state.prev && {state.prev.cols, state.prev.rows} == {frame.cols, frame.rows},
        do: state.prev

    IO.write(out, [
      if(state.prev && !prev, do: ANSI.clear(), else: []),
      ANSI.changes(prev, frame, mode: mode)
    ])

    %{state | meters: m, history: h, t: t, prev: frame}
  end

  # The panels side by side if the terminal is wide enough, else one above
  # the other; what does not fit is cut off at the right and the bottom.
  defp layout(meters, history, {cols, rows}, border) do
    top = Compose.panel(meters, title: "beam", color: border)
    under = Compose.panel(history, title: "the last two minutes", color: border)

    whole =
      if top.cols + 1 + under.cols <= cols,
        do: Compose.beside([top, under]),
        else: Compose.above([top, under])

    Compose.fit(whole, min(cols, whole.cols), min(rows - 1, whole.rows),
      align: :left,
      valign: :top
    )
  end

  defp size, do: {max(measure(:io.columns(), 80), 20), max(measure(:io.rows(), 40), 5)}

  # The terminal's own, or (written somewhere that is not one) a default.
  defp measure({:ok, n}, _default), do: n
  defp measure(_error, default), do: default
end
