defmodule Ascii.TestPieces.Blink do
  @moduledoc false
  # A piece of our own, not in the registry: a dot that blinks twice a second.
  @behaviour Ascii.Piece

  @impl true
  def meta do
    %Ascii.Meta{
      name: "blink",
      category: :ui,
      note: "a dot that blinks",
      cols: 3,
      rows: 1,
      fps: 20,
      options: %{dot: "*"}
    }
  end

  @impl true
  def init(%{dot: dot}), do: dot |> String.codepoints() |> List.first("*")

  @impl true
  def frame(dot, t, _env) do
    text = if rem(floor(t * 2), 2) == 0, do: [" ", dot, " "], else: "   "
    {text, nil, dot}
  end
end

defmodule Ascii.TestPieces.Gated do
  @moduledoc false
  # A piece whose setup waits to be let go with `send(player, :go)`, as a
  # scene's takes a while on a small board. Set up before the player has
  # started, it is never let go and raises.
  @behaviour Ascii.Piece

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "gated",
      category: :ui,
      note: "waits to start",
      cols: 1,
      rows: 1,
      fps: 20
    }

  @impl true
  def init(_options) do
    receive do
      :go -> nil
    after
      2000 -> raise "set up before the player started"
    end
  end

  @impl true
  def frame(state, _t, _env), do: {"g", nil, state}
end

defmodule Ascii.TestPieces.Waltz do
  @moduledoc false
  # Counts to three every three quarters of a second: a loop that is not a
  # whole number of frames at its rate (7.5 at 10 fps).
  @behaviour Ascii.Piece

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "waltz",
      category: :ui,
      note: "one two three",
      cols: 1,
      rows: 1,
      fps: 10,
      loop: 0.75
    }

  @impl true
  def init(_options), do: nil

  @impl true
  def frame(state, t, _env), do: {Integer.to_string(rem(floor(t / 0.25), 3) + 1), nil, state}
end

defmodule Ascii.TestPieces.Static do
  @moduledoc false
  # Noise that repeats every two seconds: a loop far too big to send, 200×100
  # cells a frame that hardly compress.
  @behaviour Ascii.Piece

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "static",
      category: :effects,
      note: "noise",
      cols: 200,
      rows: 100,
      fps: 30,
      loop: 2
    }

  @impl true
  def init(_options), do: nil

  @impl true
  def frame(state, t, _env) do
    i = rem(round(t * 30), 60)

    text =
      Enum.map_join(0..99, "\n", fn y ->
        for x <- 0..199,
            into: "",
            do: <<Enum.at(~c"!#$%&*+=?@0123456789", :erlang.phash2({i, x, y}, 20))>>
      end)

    {text, nil, state}
  end
end

defmodule Ascii.TestPieces.Counted do
  @moduledoc false
  # Counts to ten twice a second, a loop of ten frames at its 20 fps, and
  # tells the process registered as :loop_watch each time it is drawn.
  @behaviour Ascii.Piece

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "counted",
      category: :ui,
      note: "counts",
      cols: 1,
      rows: 1,
      fps: 20,
      loop: 0.5
    }

  @impl true
  def init(_options), do: nil

  @impl true
  def frame(state, t, _env) do
    if pid = Process.whereis(:loop_watch), do: send(pid, {:drawn, t})
    {Integer.to_string(rem(floor(t * 20 + 1.0e-9), 10)), nil, state}
  end
end

defmodule Ascii.TestPieces.Bar do
  @moduledoc false
  # A bar `width` cells wide, `value` percent full: its size follows its
  # options, and it counts the updates it has taken, to show its state
  # carries over. `marks` (a list of numbers) shows how shapes check lists.
  @behaviour Ascii.Piece

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "bar",
      category: :ui,
      note: "a bar",
      cols: 10,
      rows: 1,
      fps: 10,
      options: %{width: 10, value: 0, marks: []},
      bounds: %{width: {1, 80}, value: {0, 100}},
      shapes: %{marks: [0.0]}
    }

  @impl true
  def size(%{width: width}), do: {width, 1}

  @impl true
  def init(options), do: Map.put(options, :updates, 0)

  @impl true
  def update(state, options), do: Map.put(options, :updates, state.updates + 1)

  @impl true
  def frame(%{width: width, value: value} = state, _t, _env) do
    full = round(width * value / 100)
    {[String.duplicate("#", full), String.duplicate(".", width - full)], nil, state}
  end
end

defmodule Ascii.TestPieces.Noted do
  @moduledoc false
  # Sends :init to the process setting it up, if that process has put
  # :init_watch in its dictionary, to show when a still is drawn and when it
  # is kept. A flag of the test's own, rather than a registered name, so
  # tests that run at once do not see each other's.
  @behaviour Ascii.Piece

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "noted",
      category: :ui,
      note: "noted",
      cols: 2,
      rows: 1,
      fps: 10,
      options: %{mark: "#"}
    }

  @impl true
  def init(%{mark: mark}) do
    if Process.get(:init_watch), do: send(self(), :init)
    String.slice(mark <> " ", 0, 1)
  end

  @impl true
  def frame(mark, t, _env), do: {[mark, Integer.to_string(rem(floor(t), 10))], nil, mark}
end

defmodule Ascii.TestPieces.Switches do
  @moduledoc false
  # Three switches in a row, one under a cursor: a piece that can be used,
  # told in words and labelled by part. ← and → move the cursor, space flips
  # the switch under it, and a click flips the one clicked.
  @behaviour Ascii.Piece

  alias Ascii.Parts

  @impl true
  def meta,
    do: %Ascii.Meta{
      name: "switches",
      category: :ui,
      note: "three switches",
      cols: 14,
      rows: 1,
      fps: 0,
      options: %{on: [false, true, false], cursor: 0},
      bounds: %{cursor: {0, 2}},
      parts: [{"switch", nil}, {"switch.on", "#3fb950"}, {"cursor", "#d29922"}]
    }

  @impl true
  def init(options), do: options

  @impl true
  def frame(%{on: on, cursor: cursor} = state, _t, _env) do
    text =
      on
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {on?, i} ->
        if(i == cursor, do: ">", else: " ") <> if(on?, do: "[x]", else: "[ ]")
      end)

    {text, nil, state}
  end

  @impl true
  def parts(%{lines: [line]}, _options) do
    [Parts.matches(line, ~r/>|\[x\]|\[ \]/, &part/1)]
  end

  defp part(">"), do: "cursor"
  defp part("[x]"), do: "switch.on"
  defp part(_off), do: "switch"

  @impl true
  def describe(%{on: on}), do: "switches: #{Enum.count(on, & &1)} of #{length(on)} on"

  @impl true
  def handle_event({:key, "left"}, %{cursor: c} = o), do: {:ok, %{o | cursor: max(c - 1, 0)}}
  def handle_event({:key, "right"}, %{cursor: c} = o), do: {:ok, %{o | cursor: min(c + 1, 2)}}
  def handle_event({:key, " "}, %{cursor: c} = o), do: {:ok, flip(o, c)}

  def handle_event({:click, x, 0}, o) when x in 0..13 and rem(x, 5) != 4,
    do: {:ok, flip(%{o | cursor: div(x, 5)}, div(x, 5))}

  def handle_event(_event, _options), do: :ignore

  defp flip(%{on: on} = o, i), do: %{o | on: List.update_at(on, i, &(not &1))}
end
