defmodule AsciiArt.BEAMTest do
  use ExUnit.Case, async: true

  alias AsciiArt.BEAM

  defp busy(ms) do
    until = System.monotonic_time(:millisecond) + ms

    Stream.repeatedly(fn -> Enum.sum(1..500) end)
    |> Enum.find(fn _ -> System.monotonic_time(:millisecond) > until end)
  end

  test "a first sample: a core a scheduler, idle, and no busiest processes yet" do
    s = BEAM.sample()
    assert length(s.cores) == System.schedulers_online()
    assert s.top == []
    assert s.memory == :erlang.memory(:total) or s.memory > 0
    assert s.processes > 0
    assert [{memory, processes, _queue}] = s.history
    assert memory > 0 and processes == s.processes
  end

  test "from the last: scheduler use, and the busiest processes by reductions" do
    s = BEAM.sample()
    worker = Task.async(fn -> busy(150) end)
    Task.await(worker)
    s = BEAM.sample(s)

    assert Enum.all?(s.cores, &(&1 >= 0 and &1 <= 100))
    assert Enum.any?(s.cores, &(&1 > 0))
    assert s.busy == Enum.sum(s.cores) / length(s.cores)
    assert [%{pid: pid, cpu: cpu, command: command} | _] = s.top
    assert is_integer(pid) and cpu > 0 and is_binary(command)
    assert length(s.top) <= 5
  end

  test "history keeps the last 120 samples" do
    s = Enum.reduce(1..130, BEAM.sample(), fn _, s -> BEAM.sample(s) end)
    assert length(s.history) == 120
  end

  test "options each piece takes, drawn" do
    s = BEAM.sample(BEAM.sample())

    for {piece, options} <- [
          {"cpu-meters", BEAM.cpu_meters(s)},
          {"sparkline", BEAM.sparkline(s)},
          {"gauge", BEAM.gauge(s)},
          {"progress-bar", BEAM.progress_bar(s)}
        ] do
      assert {:ok, anim} = AsciiArt.new(piece, options: options)
      {frame, _} = AsciiArt.frame(anim, 0.5)
      assert length(frame.lines) == frame.rows
    end

    assert BEAM.gauge(s).label == "schedulers busy"

    assert AsciiArt.describe(AsciiArt.new!("gauge", options: BEAM.gauge(s))) =~
             "schedulers busy: "
  end
end
