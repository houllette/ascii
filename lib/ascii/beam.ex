defmodule Ascii.BEAM do
  @moduledoc """
  This VM's readings, as options for the data pieces: an htop of the BEAM.
  Its schedulers are cores, its memory is memory, its run queue is the load,
  and its processes are the process list, busiest first by reductions.

      sample = Ascii.BEAM.sample()
      # a second later
      sample = Ascii.BEAM.sample(sample)

      Ascii.put_options!(meters, Ascii.BEAM.cpu_meters(sample))
      Ascii.put_options!(history, Ascii.BEAM.sparkline(sample))
      Ascii.put_options!(busy, Ascii.BEAM.gauge(sample))

  Take a sample every second or so, each from the one before: scheduler
  use, the load and the busiest processes are measured between two
  samples, and the sparkline's history is the samples' own. `mix
  ascii.top` plays them in a terminal; in a LiveView, give them to
  `Ascii.Phoenix.live_player/1` from a timer.

  Scheduler use needs the VM's `scheduler_wall_time` flag, which the first
  sample turns on for as long as the process that took it lives (see
  `:erlang.system_flag/2`), so take samples from one long-lived process.
  """

  @mb 1_048_576
  @gb 1_073_741_824
  # Samples of history kept for the sparkline.
  @history 120
  @top 5

  @typedoc "One sample of the VM, and what it needs of the last to measure the next."
  @type t :: %__MODULE__{
          at: integer(),
          cores: [float()],
          busy: float(),
          memory: non_neg_integer(),
          memory_parts: [{atom(), float()}],
          processes: non_neg_integer(),
          run_queue: non_neg_integer(),
          load: [float()],
          uptime: non_neg_integer(),
          top: [map()],
          history: [{float(), non_neg_integer(), non_neg_integer()}],
          sched: term(),
          reductions: %{optional(pid()) => non_neg_integer()}
        }

  defstruct [
    :at,
    :sched,
    cores: [],
    busy: 0.0,
    memory: 0,
    memory_parts: [],
    processes: 0,
    run_queue: 0,
    load: [0.0, 0.0, 0.0],
    uptime: 0,
    top: [],
    history: [],
    reductions: %{}
  ]

  @doc """
  A sample of the VM, measured from `prev` (`nil` for the first, which
  measures no scheduler use and no busiest processes yet).
  """
  @spec sample(prev :: t() | nil) :: t()
  def sample(prev \\ nil) do
    if prev == nil, do: :erlang.system_flag(:scheduler_wall_time, true)
    sched = :erlang.statistics(:scheduler_wall_time)
    memory = :erlang.memory()
    total = memory[:total]
    run_queue = :erlang.statistics(:total_run_queue_lengths)
    pids = Process.list()

    cores =
      if prev,
        do: utilization(prev.sched, sched),
        else: List.duplicate(0.0, System.schedulers_online())

    # Run-queue averages over about 1, 5 and 15 samples, as load averages are.
    load =
      for {avg, k} <- Enum.zip((prev && prev.load) || [0, 0, 0], [1, 5, 15]),
          do: avg + (run_queue - avg) / k

    reductions = Map.new(pids, &{&1, reductions(&1)})

    %__MODULE__{
      at: System.monotonic_time(:millisecond),
      sched: sched,
      cores: cores,
      busy: if(cores == [], do: 0.0, else: Enum.sum(cores) / length(cores)),
      memory: total,
      memory_parts:
        for(k <- [:processes, :binary, :ets, :code, :atom], do: {k, memory[k] / total * 100}),
      processes: length(pids),
      run_queue: run_queue,
      load: load,
      uptime: div(elem(:erlang.statistics(:wall_clock), 0), 1000),
      reductions: reductions,
      top: top(prev && prev.reductions, reductions, total),
      history:
        Enum.take(
          ((prev && prev.history) || []) ++ [{total / @mb, length(pids), run_queue}],
          -@history
        )
    }
  end

  # Each normal scheduler's share of the wall time between two samples that
  # it was busy, in percent, as :scheduler.utilization/2 has it.
  defp utilization(before, now) when is_list(before) and is_list(now) do
    normal = System.schedulers()
    before = Map.new(before, fn {id, active, total} -> {id, {active, total}} end)

    for {id, active, total} <- Enum.sort(now),
        id <= normal,
        {a0, t0} = Map.get(before, id, {active, total}) do
      if total > t0, do: (active - a0) / (total - t0) * 100, else: 0.0
    end
  end

  defp utilization(_before, _now), do: List.duplicate(0.0, System.schedulers_online())

  defp reductions(pid) do
    case Process.info(pid, :reductions) do
      {:reductions, n} -> n
      nil -> 0
    end
  end

  # The busiest processes since the last sample, by reductions.
  defp top(nil, _now, _total), do: []

  defp top(before, now, total) do
    deltas = for {pid, n} <- now, d = n - Map.get(before, pid, n), d > 0, do: {pid, d}
    sum = deltas |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> max(1)

    deltas
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(@top)
    |> Enum.flat_map(fn {pid, d} ->
      case Process.info(pid, [
             :memory,
             :registered_name,
             :initial_call,
             :current_function,
             :status
           ]) do
        nil -> []
        info -> [process(pid, info, d / sum * 100, total)]
      end
    end)
  end

  defp process(pid, info, cpu, total) do
    [_node, n, _serial] =
      pid
      |> :erlang.pid_to_list()
      |> to_string()
      |> String.trim("<")
      |> String.trim(">")
      |> String.split(".")

    %{
      pid: String.to_integer(n),
      user: application(pid),
      cpu: cpu,
      mem: info[:memory] / total * 100,
      res: info[:memory] / @gb,
      state: if(info[:status] == :running, do: "R", else: "S"),
      command: name(info)
    }
  end

  # Its registered name, or the module it was started in (or, for a plain
  # spawn, the one it is running).
  defp name(info) do
    module =
      case {info[:registered_name], info[:initial_call]} do
        {[], {:erlang, :apply, _}} -> elem(info[:current_function] || {:erlang, :apply, 0}, 0)
        {[], {module, _, _}} -> module
        {name, _} -> name
      end

    module |> inspect() |> String.replace_prefix("Elixir.", "")
  end

  defp application(pid) do
    case :application.get_application(pid) do
      {:ok, app} -> Atom.to_string(app)
      :undefined -> "-"
    end
  end

  @doc """
  Options for `cpu-meters`: the schedulers as cores, memory in gigabytes
  against the next half gigabyte up, the run queue's averages as the load,
  the process count as tasks, uptime, and the busiest processes.
  """
  @spec cpu_meters(sample :: t()) :: map()
  def cpu_meters(%__MODULE__{} = s) do
    %{
      cores: s.cores,
      memory: [s.memory / @gb, max(1, Float.ceil(s.memory / @gb * 4) / 2)],
      swap: [0, 1],
      load: s.load,
      tasks: s.processes,
      uptime: s.uptime,
      processes: s.top
    }
  end

  @doc """
  Options for `sparkline`: memory in megabytes, the process count and the
  run queue, a sample at a time over the last #{@history}. `rate` is
  samples a second, for its time axis (default 1).
  """
  @spec sparkline(sample :: t(), opts :: [rate: number()]) :: map()
  def sparkline(%__MODULE__{history: history}, opts \\ []) do
    %{
      series: [
        %{label: "memory", unit: " mb", digits: 1, values: Enum.map(history, &elem(&1, 0))},
        %{label: "processes", unit: "", values: Enum.map(history, &elem(&1, 1))},
        %{label: "run queue", unit: "", lo: 0, values: Enum.map(history, &elem(&1, 2))}
      ],
      rate: Keyword.get(opts, :rate, 1)
    }
  end

  @doc "Options for `gauge`: the schedulers' average use."
  @spec gauge(sample :: t()) :: map()
  def gauge(%__MODULE__{busy: busy}),
    do: %{label: "schedulers busy", unit: "%", min: 0, max: 100, value: busy}

  @doc "Options for `progress-bar`: where the memory goes, in percent of it."
  @spec progress_bar(sample :: t()) :: map()
  def progress_bar(%__MODULE__{memory_parts: parts}) do
    %{
      values: Enum.map(parts, &elem(&1, 1)),
      labels: Enum.map(parts, &Atom.to_string(elem(&1, 0)))
    }
  end
end
