defmodule AsciiArt.TelemetryTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Telemetry, as: Feed

  # Shaped as Telemetry.Metrics' own, which this library does not depend on.
  defmodule Metrics.Summary do
    defstruct [:name, :event_name, :measurement, :keep, :unit, reporter_options: []]
  end

  defp event(name), do: [:ascii_art_test, name, :"n#{System.unique_integer([:positive])}"]

  # A feed that samples only when told, so the test says when.
  defp feed(metrics, opts \\ []) do
    start_supervised!({Feed, [metrics: metrics, every: 3_600_000] ++ opts})
  end

  defp sample(feed) do
    send(feed, :sample)
    Feed.readings(feed)
  end

  test "each sample, a reading of each metric by its kind" do
    e = event(:request)

    feed =
      feed([
        %{name: "requests", event: e, measurement: :duration, kind: :counter},
        %{name: "busy", event: e, measurement: :duration, kind: :sum, unit: "ms"},
        %{name: "mean", event: e, measurement: :duration, kind: :summary},
        %{name: "last", event: e, measurement: :duration}
      ])

    for d <- [10, 20, 60], do: :telemetry.execute(e, %{duration: d}, %{})

    assert sample(feed) == [
             %{label: "requests", unit: "", values: [3]},
             %{label: "busy", unit: "ms", values: [90]},
             %{label: "mean", unit: "", values: [30.0]},
             %{label: "last", unit: "", values: [60]}
           ]

    # A quiet sample: none counted, a mean of nothing left out, the last kept.
    assert [%{values: [3, 0]}, %{values: [90, 0]}, %{values: [30.0]}, %{values: [60, 60]}] =
             sample(feed)
  end

  test "Telemetry.Metrics definitions: the measurement function, keep, unit and label" do
    e = event(:query)

    feed =
      feed([
        %Metrics.Summary{
          name: [:ascii_art_test, :query, :total_time],
          event_name: e,
          measurement: fn m -> m.total / 1000 end,
          keep: &(&1.source == "users"),
          unit: :millisecond
        },
        %Metrics.Summary{
          name: [:db, :total],
          event_name: e,
          measurement: fn m, meta -> m.total * meta.weight end,
          reporter_options: [label: "weighted"]
        }
      ])

    :telemetry.execute(e, %{total: 4000}, %{source: "users", weight: 2})
    :telemetry.execute(e, %{total: 2000}, %{source: "posts", weight: 1})

    assert sample(feed) == [
             %{label: "query", unit: "ms", values: [4.0]},
             %{label: "weighted", unit: "", values: [5.0e3]}
           ]
  end

  test "a window of samples, the oldest dropping off" do
    e = event(:tick)
    feed = feed([%{name: "n", event: e, measurement: :n, kind: :sum}], window: 3)

    for n <- 1..5 do
      :telemetry.execute(e, %{n: n}, %{})
      sample(feed)
    end

    assert [%{values: [3, 4, 5]}] = Feed.readings(feed)
  end

  test "subscribers are sent the readings each sample; players are fed theirs" do
    e = event(:load)
    {:ok, player} = AsciiArt.Player.start_link(piece: "gauge", to: self())

    feed =
      feed([%{name: "load", event: e, measurement: :value, unit: "%"}],
        players: [{player, &Feed.gauge/1}]
      )

    :ok = Feed.subscribe(feed)
    :telemetry.execute(e, %{value: 73}, %{})
    send(feed, :sample)

    assert_receive {:ascii_art_telemetry, ^feed, [%{label: "load", values: [73]}]}
    assert_receive {:ascii_art_frame, _ref, frame}, 1000
    assert frame.text =~ "73%" or match?(%{options: %{value: 73}}, :sys.get_state(player).anim)
  end

  test "options for a sparkline and a gauge" do
    readings = [
      %{label: "memory", unit: "mb", values: [1, 2]},
      %{label: "load", unit: "%", values: [40, 50]},
      %{label: "count", unit: "", values: []}
    ]

    assert Feed.sparkline(readings, every: 500) == %{
             series: [
               %{label: "memory", unit: " mb", values: [1, 2]},
               %{label: "load", unit: "%", values: [40, 50]},
               %{label: "count", unit: "", values: []}
             ],
             rate: 2.0
           }

    assert Feed.sparkline(readings, only: ["load"]).series == [
             %{label: "load", unit: "%", values: [40, 50]}
           ]

    assert Feed.gauge(readings, label: "load", max: 200) ==
             %{label: "load", unit: "%", value: 50, max: 200}

    assert Feed.gauge(readings) == %{label: "memory", unit: " mb", value: 2}
    assert Feed.gauge([]) == %{}
    assert {:ok, _} = AsciiArt.new("sparkline", options: Feed.sparkline(readings))
  end

  test "its handlers go when it stops" do
    e = event(:gone)
    feed = feed([%{name: "x", event: e, measurement: :x}])
    assert Enum.any?(:telemetry.list_handlers(e), &(&1.id == {Feed, feed}))
    stop_supervised!(Feed)
    assert :telemetry.list_handlers(e) == []
  end
end
