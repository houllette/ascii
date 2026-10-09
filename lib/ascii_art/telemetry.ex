if Code.ensure_loaded?(:telemetry) do
  defmodule AsciiArt.Telemetry do
    @moduledoc """
    Your app's `:telemetry` events as live data for the pieces: a process
    that keeps a reading of each metric a sample at a time, for a
    sparkline's series, a gauge's needle or a progress bar.

        children = [
          {AsciiArt.Telemetry,
           name: MyApp.Readings,
           metrics: [
             Telemetry.Metrics.last_value("vm.memory.total", unit: {:byte, :megabyte}),
             Telemetry.Metrics.counter("phoenix.endpoint.stop.duration", reporter_options: [label: "requests"]),
             Telemetry.Metrics.summary("my_app.repo.query.total_time", unit: {:native, :millisecond})
           ]}
        ]

        # in a LiveView
        if connected?(socket), do: AsciiArt.Telemetry.subscribe(MyApp.Readings)

        def handle_info({:ascii_art_telemetry, _feed, readings}, socket),
          do: {:noreply, assign(socket, history: AsciiArt.Telemetry.sparkline(readings))}

        <AsciiArt.Phoenix.live_player id="history" piece="sparkline" options={@history} />

    Or have it feed players itself, each sample:

        {AsciiArt.Telemetry, metrics: metrics, players: [{MyApp.History, &AsciiArt.Telemetry.sparkline/1}]}

    ## Metrics

    `Telemetry.Metrics` definitions, as for any reporter (the
    `telemetry_metrics` package; it need not be a dependency of this
    library), or maps of the same: `%{name: "db", event: [:my_app, :repo,
    :query], measurement: :total_time, kind: :summary, unit: "ms"}`. Each
    sample, every `:every` milliseconds, gives each metric one reading:

      * `last_value` - its latest measurement (kept until another comes);
      * `counter` - how many events came;
      * `sum` - their measurements added up;
      * `summary`, `distribution` - their mean, or nothing if none came.

    A metric's label is its `reporter_options[:label]`, else its name's last
    part but one, as `memory` for `vm.memory.total`; its unit is the one it
    converts to.

    ## Options

      * `:metrics` - the metrics (required).
      * `:every` - milliseconds a sample (default 1000).
      * `:window` - samples kept of each metric (default 120).
      * `:players` - `{player, fun}` pairs: each sample, `fun` turns the
        readings into options for the player (`AsciiArt.Player.set_options/2`).
      * `:name` - to register the process.

    Handlers run in the processes that emit the events, so each is a
    message to this process and no more. They are detached when it stops.
    Only available when `telemetry` is a dependency (Phoenix brings it).
    """
    use GenServer

    @typedoc "A metric's readings, oldest first, by its label, with its unit."
    @type readings :: [%{label: String.t(), unit: String.t(), values: [number()]}]

    @doc false
    def child_spec(opts),
      do: %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}

    @doc "Starts a feed; see the module docs for the options."
    @spec start_link(opts :: keyword()) :: GenServer.on_start()
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

    @doc """
    Sends the calling process `{:ascii_art_telemetry, feed, readings}` after
    every sample, until it exits.
    """
    @spec subscribe(feed :: GenServer.server()) :: :ok
    def subscribe(feed), do: GenServer.call(feed, :subscribe)

    @doc "The readings so far."
    @spec readings(feed :: GenServer.server()) :: readings()
    def readings(feed), do: GenServer.call(feed, :readings)

    @doc """
    Options for `sparkline`: a series a metric (the first five; `:only`
    picks by label), and its rate, samples a second.
    """
    @spec sparkline(readings :: readings(), opts :: [only: [String.t()], every: pos_integer()]) ::
            map()
    def sparkline(readings, opts \\ []) do
      only = Keyword.get(opts, :only)

      series =
        for %{label: label, unit: unit, values: values} <- readings,
            only == nil or label in only,
            do: %{label: label, unit: unit(unit), values: values}

      %{series: Enum.take(series, 5), rate: 1000 / Keyword.get(opts, :every, 1000)}
    end

    @doc """
    Options for `gauge`: the latest reading of the metric `label` (the first,
    if not given), its label and unit; `:min` and `:max` for the dial.
    """
    @spec gauge(readings :: readings(), opts :: [label: String.t(), min: number(), max: number()]) ::
            map()
    def gauge(readings, opts \\ []) do
      reading =
        case Keyword.fetch(opts, :label) do
          {:ok, label} -> Enum.find(readings, &(&1.label == label))
          :error -> List.first(readings)
        end

      case reading do
        nil ->
          %{}

        %{label: label, unit: unit, values: values} ->
          Map.merge(
            %{label: label, unit: unit(unit), value: List.last(values)},
            Map.new(Keyword.take(opts, [:min, :max]))
          )
      end
    end

    defp unit(""), do: ""
    defp unit("%"), do: "%"
    defp unit(unit), do: " " <> unit

    @impl true
    def init(opts) do
      Process.flag(:trap_exit, true)
      metrics = opts |> Keyword.fetch!(:metrics) |> Enum.with_index() |> Enum.map(&metric/1)
      id = {__MODULE__, self()}

      :ok =
        :telemetry.attach_many(
          id,
          metrics |> Enum.map(& &1.event) |> Enum.uniq(),
          &__MODULE__.handle_event/4,
          %{
            pid: self(),
            metrics: Enum.map(metrics, &Map.take(&1, [:index, :event, :measure, :keep]))
          }
        )

      every = Keyword.get(opts, :every, 1000)
      Process.send_after(self(), :sample, every)

      {:ok,
       %{
         id: id,
         metrics: metrics,
         every: every,
         window: Keyword.get(opts, :window, 120),
         players: Keyword.get(opts, :players, []),
         subscribers: %{},
         open: Map.new(metrics, &{&1.index, []}),
         values: Map.new(metrics, &{&1.index, []}),
         last: %{}
       }}
    end

    # A metric as this feed keeps it, from a Telemetry.Metrics struct or a map.
    defp metric({%{__struct__: struct} = m, index}) do
      kind =
        struct |> Module.split() |> List.last() |> Macro.underscore() |> kind()

      label =
        get_in(m, [Access.key(:reporter_options, []), :label]) ||
          m.name |> Enum.drop(-1) |> List.last() |> to_string()

      %{
        index: index,
        event: m.event_name,
        measure: m.measurement,
        keep: Map.get(m, :keep),
        kind: kind,
        label: label,
        unit: unit_name(Map.get(m, :unit))
      }
    end

    defp metric({%{} = m, index}) do
      %{
        index: index,
        event: Map.fetch!(m, :event),
        measure: Map.fetch!(m, :measurement),
        keep: Map.get(m, :keep),
        kind: kind(to_string(Map.get(m, :kind, :last_value))),
        label: to_string(Map.fetch!(m, :name)),
        unit: unit_name(Map.get(m, :unit))
      }
    end

    defp kind("counter"), do: :counter
    defp kind("sum"), do: :sum
    defp kind("summary"), do: :mean
    defp kind("distribution"), do: :mean
    defp kind(_last_value), do: :last_value

    @units %{
      unit: "",
      byte: "b",
      kilobyte: "kb",
      megabyte: "mb",
      gigabyte: "gb",
      second: "s",
      millisecond: "ms",
      microsecond: "us",
      nanosecond: "ns",
      percent: "%"
    }

    defp unit_name(nil), do: ""
    defp unit_name(unit) when is_atom(unit), do: Map.get(@units, unit, Atom.to_string(unit))
    defp unit_name(unit) when is_binary(unit), do: unit
    defp unit_name(_unit), do: ""

    @doc false
    # In the process that emitted the event: each metric's measurement, if
    # it has one and its `keep` takes the event, sent on.
    def handle_event(event, measurements, metadata, %{pid: pid, metrics: metrics}) do
      for %{event: ^event, index: index, measure: measure, keep: keep} <- metrics,
          keep == nil or keep.(metadata),
          value = measure(measure, measurements, metadata),
          is_number(value) do
        send(pid, {:measure, index, value})
      end

      :ok
    end

    defp measure(key, measurements, _metadata) when is_atom(key), do: Map.get(measurements, key)
    defp measure(fun, measurements, _metadata) when is_function(fun, 1), do: fun.(measurements)

    defp measure(fun, measurements, metadata) when is_function(fun, 2),
      do: fun.(measurements, metadata)

    defp measure(_measure, _measurements, _metadata), do: nil

    @impl true
    def handle_call(:subscribe, {pid, _}, state) do
      ref = Process.monitor(pid)
      {:reply, :ok, put_in(state.subscribers[pid], ref)}
    end

    def handle_call(:readings, _from, state), do: {:reply, kept(state), state}

    @impl true
    def handle_info({:measure, index, value}, state),
      do: {:noreply, update_in(state.open[index], &[value | &1])}

    def handle_info(:sample, state) do
      Process.send_after(self(), :sample, state.every)
      state = close(state)
      readings = kept(state)

      for {pid, _ref} <- state.subscribers,
          do: send(pid, {:ascii_art_telemetry, self(), readings})

      for {player, fun} <- state.players, do: AsciiArt.Player.set_options(player, fun.(readings))

      {:noreply, state}
    end

    def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
      do: {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}

    def handle_info(_message, state), do: {:noreply, state}

    # Each metric's reading for the sample now closing, from what came in it.
    defp close(state) do
      {values, last} =
        Enum.reduce(state.metrics, {state.values, state.last}, fn %{index: i, kind: kind},
                                                                  {values, last} ->
          came = Enum.reverse(state.open[i])

          case reading(kind, came, last[i]) do
            nil ->
              {values, last}

            v ->
              {Map.update!(values, i, &Enum.take(&1 ++ [v], -state.window)), Map.put(last, i, v)}
          end
        end)

      %{state | values: values, last: last, open: Map.new(state.metrics, &{&1.index, []})}
    end

    defp reading(:counter, came, _last), do: length(came)
    defp reading(:sum, came, _last), do: Enum.sum(came)
    defp reading(:mean, [], _last), do: nil
    defp reading(:mean, came, _last), do: Enum.sum(came) / length(came)
    defp reading(:last_value, [], last), do: last
    defp reading(:last_value, came, _last), do: List.last(came)

    defp kept(state) do
      for %{index: i, label: label, unit: unit} <- state.metrics,
          do: %{label: label, unit: unit, values: state.values[i]}
    end

    @impl true
    def terminate(_reason, state), do: :telemetry.detach(state.id)
  end
end
