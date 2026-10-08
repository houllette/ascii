defmodule AsciiArt.Player do
  @moduledoc """
  Plays a piece in real time: a process that draws a frame every `1/fps`
  seconds and hands it on.

      {:ok, player} = AsciiArt.Player.start_link(piece: "donut")

      receive do
        {:ascii_art_frame, _ref, frame} -> IO.write(AsciiArt.Render.ANSI.render(frame))
      end

  ## Where frames go

  Started with `start_link/1` or `start/1`, a player sends its frames to the
  process that started it (or `:to`) as `{:ascii_art_frame, ref,
  %AsciiArt.Frame{}}`, and stops when that process, its owner, exits. Given a
  `:callback`, it calls that instead, in the player's process, and has no
  owner.

  Any process can also `subscribe/1` to a player and receive the same
  messages until it unsubscribes or exits, and `frame/1` returns the latest
  frame. That is how one player serves many viewers:

      children = [
        {AsciiArt.Player, piece: "elixir", name: MyApp.Logo}
      ]

      # in each LiveView
      def mount(_params, _session, socket) do
        if connected?(socket), do: AsciiArt.Player.subscribe(MyApp.Logo)
        {:ok, assign(socket, frame: AsciiArt.Player.frame(MyApp.Logo))}
      end

      def handle_info({:ascii_art_frame, _ref, frame}, socket),
        do: {:noreply, assign(socket, frame: frame)}

  Under a supervisor (`child_spec/1`) a player has no owner unless given
  `:to`: it sends nothing to the supervisor, only to its callback and its
  subscribers. A player with no one to send to holds its frame and does no
  work, and play time waits with it, until someone subscribes.

  ## Time

  Play time advances as upstream's `mount` advances it: by the real time
  since the last frame, at most 100 ms a frame, and not at all while paused.
  Ticks are scheduled against the monotonic clock, so they keep their pace
  rather than drift by the time each frame takes to draw.

  `start_link/1` checks the piece and its options, and returns their error
  if there is one, without starting a process. It returns as soon as the
  player has started; the player then sets the piece up (a scene takes up to
  a second, more on a small board) before it does anything else, so a call
  made meanwhile waits for it. A supervisor starting a scene's player is not
  held up.

  A piece that closes a loop (`AsciiArt.Meta`'s `loop`), played with its
  default options and frame rate, is drawn once a frame of its cycle, as
  play first reaches each, and then repeated, so after one cycle it costs
  nothing to play: the frames are kept, up to a megabyte. Frames come at the
  cycle's places rather than at the exact play time, which is every
  `1/fps` of a second anyway; a frame's `t` is still the play time.

  It needs nothing from Phoenix, so it serves a terminal app (see
  `mix ascii_art.play`) or a device: on Nerves, start it under your own
  supervisor and draw `frame.lines` and `frame.colors` to the display in the
  callback.

  ## Options

    * `:piece` (required) - a slug or module.
    * `:to` - the owner: the pid to send frames to, which the player stops
      with. The caller by default, or no one under a supervisor; `nil` for no
      one.
    * `:callback` - a function of one frame, instead of messages to an owner.
    * `:ref` - the tag on each message (a fresh reference by default; see
      `ref/1`).
    * `:cache` - keep and repeat the frames of a loop (default `true`).
    * `:options`, `:fps`, `:paper`, `:color` - as for `AsciiArt.new/2`.
    * `:name` - registers the player. Under a supervisor it is also the
      child's id, so one supervisor can hold several named players.
  """
  use GenServer

  alias AsciiArt.{Animation, Frame}

  @max_step 100

  @doc "Starts a player linked to the caller. See the module docs for options."
  @spec start_link(opts :: keyword()) :: GenServer.on_start() | AsciiArt.error()
  def start_link(opts), do: launch(opts, &GenServer.start_link/3)

  @doc "Starts a player without a link."
  @spec start(opts :: keyword()) :: GenServer.on_start() | AsciiArt.error()
  def start(opts), do: launch(opts, &GenServer.start/3)

  @doc """
  A child spec for a supervisor: `{AsciiArt.Player, piece: "donut", name: MyApp.Donut}`.

  The player sends frames to no one by default, rather than to the
  supervisor that starts it; see the module docs.
  """
  @spec child_spec(opts :: keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [Keyword.put_new(opts, :to, nil)]}
    }
  end

  # Checked here, in the caller, so a bad piece or option is an error to
  # return rather than a process exit for the caller to trap.
  defp launch(opts, start) do
    with {:ok, piece} <- fetch(opts, :piece),
         {:ok, anim} <-
           AsciiArt.prepare(piece, Keyword.take(opts, [:options, :fps, :paper, :color])),
         {:ok, receiver} <- receiver(Keyword.get(opts, :callback), Keyword.get(opts, :to, self())) do
      ref = Keyword.get_lazy(opts, :ref, &make_ref/0)
      cache? = Keyword.get(opts, :cache, true) == true
      start.(__MODULE__, {anim, receiver, ref, cache?}, Keyword.take(opts, [:name]))
    end
  end

  defp fetch(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_option, key}}
    end
  end

  # A callback replaces messages to an owner.
  defp receiver(nil, to) when is_pid(to) or to == nil, do: {:ok, {nil, to}}
  defp receiver(nil, _to), do: {:error, {:invalid_option, :to}}
  defp receiver(callback, _to) when is_function(callback, 1), do: {:ok, {callback, nil}}
  defp receiver(_callback, _to), do: {:error, {:invalid_option, :callback}}

  @doc "The tag on this player's frame messages."
  @spec ref(player :: GenServer.server()) :: term()
  def ref(player), do: GenServer.call(player, :ref)

  @doc """
  The latest frame drawn. Frame 0 until the player has played; while the
  piece is still being set up, this waits for it, up to `timeout` ms.
  """
  @spec frame(player :: GenServer.server(), timeout :: timeout()) :: Frame.t()
  def frame(player, timeout \\ 5000), do: GenServer.call(player, :frame, timeout)

  @doc """
  Sends the caller every frame from now on, as the owner gets them, until it
  calls `unsubscribe/1` or exits. Subscribing twice changes nothing.
  """
  @spec subscribe(player :: GenServer.server(), timeout :: timeout()) :: :ok
  def subscribe(player, timeout \\ 5000), do: GenServer.call(player, :subscribe, timeout)

  @doc "Stops sending the caller frames."
  @spec unsubscribe(player :: GenServer.server()) :: :ok
  def unsubscribe(player), do: GenServer.call(player, :unsubscribe)

  @doc "Holds the current frame; play time stops."
  @spec pause(player :: GenServer.server()) :: :ok
  def pause(player), do: GenServer.call(player, :pause)

  @doc "Plays on from where it paused."
  @spec resume(player :: GenServer.server()) :: :ok
  def resume(player), do: GenServer.call(player, :resume)

  @doc """
  New options for the piece, merged over its own (see
  `AsciiArt.put_options/2`): for live data, a reading or the latest samples.
  The new picture is drawn and sent at once.
  """
  @spec set_options(player :: GenServer.server(), options :: map() | keyword()) ::
          :ok | AsciiArt.error()
  def set_options(player, options), do: GenServer.call(player, {:options, options})

  @doc "Changes the frame rate, 0 to 60; 0 holds the picture."
  @spec set_fps(player :: GenServer.server(), fps :: number()) ::
          :ok | {:error, {:invalid_option, :fps}}
  def set_fps(player, fps), do: GenServer.call(player, {:fps, fps})

  @doc "Stops the player."
  @spec stop(player :: GenServer.server()) :: :ok
  def stop(player), do: GenServer.stop(player)

  @impl true
  def init({anim, {callback, to}, ref, cache?}) do
    if to, do: Process.monitor(to)

    state = %{
      anim: anim,
      cache?: cache?,
      cycle: nil,
      frame: nil,
      to: to,
      callback: callback,
      subscribers: %{},
      ref: ref,
      t: 0.0,
      paused: false,
      last: nil,
      next_at: nil,
      timer: nil
    }

    {:ok, state, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    state = %{state | anim: Animation.setup(state.anim)} |> keep_cycle()
    {:noreply, state |> draw() |> wake()}
  end

  @impl true
  def handle_call(:ref, _from, state), do: {:reply, state.ref, state}
  def handle_call(:frame, _from, state), do: {:reply, state.frame, state}

  def handle_call(:subscribe, {pid, _}, %{to: pid} = state), do: {:reply, :ok, state}

  def handle_call(:subscribe, {pid, _}, state) when is_map_key(state.subscribers, pid),
    do: {:reply, :ok, state}

  def handle_call(:subscribe, {pid, _}, state) do
    subscribers = Map.put(state.subscribers, pid, Process.monitor(pid))
    {:reply, :ok, wake(%{state | subscribers: subscribers})}
  end

  def handle_call(:unsubscribe, {pid, _}, state) do
    {monitor, subscribers} = Map.pop(state.subscribers, pid)
    if monitor, do: Process.demonitor(monitor, [:flush])
    {:reply, :ok, idle(%{state | subscribers: subscribers})}
  end

  def handle_call(:pause, _from, state), do: {:reply, :ok, %{cancel(state) | paused: true}}

  def handle_call(:resume, _from, %{paused: true} = state),
    do: {:reply, :ok, wake(%{state | paused: false})}

  def handle_call(:resume, _from, state), do: {:reply, :ok, state}

  def handle_call({:fps, fps}, _from, state) when is_number(fps) and fps >= 0 and fps <= 60 do
    state = %{cancel(state) | anim: %{state.anim | fps: round(fps)}, next_at: now()}
    {:reply, :ok, state |> keep_cycle() |> schedule()}
  end

  def handle_call({:fps, _fps}, _from, state),
    do: {:reply, {:error, {:invalid_option, :fps}}, state}

  def handle_call({:options, options}, _from, state) do
    case AsciiArt.put_options(state.anim, options) do
      {:ok, anim} -> {:reply, :ok, %{state | anim: anim} |> keep_cycle() |> draw()}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:tick, timer}, %{timer: timer} = state) do
    now = now()
    t = state.t + min(now - state.last, @max_step) / 1000
    state = draw(%{state | t: t, last: now, timer: nil})
    {:noreply, schedule(state)}
  end

  def handle_info({:tick, _stale}, state), do: {:noreply, state}

  def handle_info({:DOWN, _, :process, pid, _}, %{to: pid} = state), do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, pid, _}, state) do
    case Map.fetch(state.subscribers, pid) do
      {:ok, ^monitor} ->
        {:noreply, idle(%{state | subscribers: Map.delete(state.subscribers, pid)})}

      _ ->
        {:noreply, state}
    end
  end

  defp draw(state) do
    {frame, state} = next(state)
    message = {:ascii_art_frame, state.ref, frame}
    if state.callback, do: state.callback.(frame)
    if state.to, do: send(state.to, message)
    for {pid, _} <- state.subscribers, do: send(pid, message)
    %{state | frame: frame}
  end

  # A piece that closes a loop, at the options and rate its period was
  # measured at, is drawn once a frame of its cycle, as play first reaches
  # it, and then repeated: after the first cycle it costs nothing. Its frames
  # are kept up to @cache_bytes.
  @cache_bytes 1_048_576

  defp keep_cycle(%{cache?: true, anim: anim} = state) do
    case Animation.cycle(anim) do
      {n, rate, true} -> %{state | cycle: %{n: n, rate: rate, frames: %{}, bytes: 0}}
      _ -> %{state | cycle: nil}
    end
  end

  defp keep_cycle(state), do: %{state | cycle: nil}

  defp next(%{cycle: %{n: n, rate: rate, frames: frames} = cycle, t: t} = state) do
    k = rem(trunc(t * rate), n)

    case frames do
      %{^k => frame} ->
        {%{frame | t: t}, state}

      _ ->
        {frame, anim} = AsciiArt.frame(state.anim, k / rate)
        bytes = cycle.bytes + byte_size(frame.text) + byte_size(frame.colors || "")

        cycle =
          if bytes <= @cache_bytes,
            do: %{cycle | frames: Map.put(frames, k, frame), bytes: bytes},
            else: nil

        {%{frame | t: t}, %{state | anim: anim, cycle: cycle}}
    end
  end

  defp next(state) do
    {frame, anim} = AsciiArt.frame(state.anim, state.t)
    {frame, %{state | anim: anim}}
  end

  # Playing when not paused and someone gets the frames.
  defp active?(%{paused: true}), do: false
  defp active?(state), do: state.callback != nil or state.to != nil or state.subscribers != %{}

  # Starts the ticks if they should run and do not, counting play time from
  # now: time spent paused or with no one watching is not played.
  defp wake(%{timer: nil} = state) do
    if active?(state) do
      now = now()
      schedule(%{state | last: now, next_at: now})
    else
      state
    end
  end

  defp wake(state), do: state

  defp idle(state), do: if(active?(state), do: state, else: cancel(state))

  # The next tick, a frame's interval after the last one was due, so the pace
  # holds; after a stall, from now.
  defp schedule(%{anim: %Animation{fps: 0}} = state), do: state

  defp schedule(%{anim: %Animation{fps: fps}} = state) do
    if active?(state) do
      now = now()
      due = state.next_at + 1000 / fps
      due = if due < now - 1000 / fps, do: now, else: due
      timer = make_ref()
      Process.send_after(self(), {:tick, timer}, max(0, round(due - now)))
      %{state | next_at: due, timer: timer}
    else
      state
    end
  end

  # A cancelled tick still arrives, and is ignored as stale.
  defp cancel(state), do: %{state | timer: nil}

  defp now, do: System.monotonic_time(:microsecond) / 1000
end
