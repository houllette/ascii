defmodule AsciiArt.ExRatatui.ViewerTest do
  use ExUnit.Case, async: true

  alias AsciiArt.ExRatatui.Viewer
  alias ExRatatui.CellSession
  alias ExRatatui.Event.{Key, Resize}
  alias ExRatatui.Runtime

  @size %ExRatatui.Frame{width: 100, height: 40}

  defp key(code, modifiers \\ []), do: %Key{code: code, kind: "press", modifiers: modifiers}

  # The viewer's callbacks are called here, in the test process, so its
  # player sends its frames here.
  defp mount(opts) do
    {:ok, state} = Viewer.mount(opts)
    state
  end

  # The next frame it shows: one from a piece it played before is passed
  # over.
  defp next_frame(state) do
    assert_receive {:ascii_art_frame, _ref, _frame} = message, 2000

    case Viewer.handle_info(message, state) do
      {:noreply, state} -> state
      {:noreply, ^state, render?: false} -> next_frame(state)
    end
  end

  # The players linked to this process: the viewer's, while its callbacks
  # are called here.
  defp players do
    {:links, links} = Process.info(self(), :links)

    Enum.filter(links, fn pid ->
      match?({:dictionary, %{"$initial_call": {AsciiArt.Player, :init, 1}}}, dictionary(pid))
    end)
  end

  defp dictionary(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> {:dictionary, Map.new(dictionary)}
      nil -> nil
    end
  end

  defp event(state, event) do
    {:noreply, state} = Viewer.handle_event(event, state)
    state
  end

  defp flush_frames do
    receive do
      {:ascii_art_frame, _, _} -> flush_frames()
    after
      0 -> :ok
    end
  end

  # The cells it draws on a screen of `size`, row by row.
  defp cells(state, %{width: width, height: height} = size) do
    session = CellSession.new(width, height)
    :ok = CellSession.draw(session, Viewer.render(state, size))
    snapshot = CellSession.take_cells(session)
    CellSession.close(session)
    snapshot.cells
  end

  # The same as text.
  defp screen(state, size \\ @size) do
    state
    |> cells(size)
    |> Enum.chunk_every(size.width)
    |> Enum.map_join("\n", fn row -> Enum.map_join(row, & &1.symbol) end)
  end

  defp still_lines(piece, opts \\ []) do
    {:ok, frame} = AsciiArt.still(piece, opts)
    frame.lines
  end

  test "plays the piece in the middle of the screen, under its name" do
    state = [piece: "spinners"] |> mount() |> next_frame()
    screen = screen(state)
    assert screen =~ "spinners"
    assert screen =~ "space pause"

    lines = String.split(screen, "\n")
    [first | _] = still_lines("spinners")
    assert Enum.any?(lines, &(&1 =~ first))
  end

  test "before its first frame, its name on an empty frame of its size" do
    state = mount(piece: "elixir")
    screen = screen(state)
    assert screen =~ "elixir"
    refute screen =~ "8888"
  end

  test "space pauses it and plays it on" do
    state = [piece: "spinners"] |> mount() |> next_frame()
    state = event(state, key(" "))
    flush_frames()
    refute_receive {:ascii_art_frame, _, _}, 300
    assert screen(state) =~ "paused"

    state = event(state, key(" "))
    assert_receive {:ascii_art_frame, _, _}, 1000
    refute screen(state) =~ "paused"
  end

  test "paused before its first frame, it holds that frame" do
    state = mount(piece: "spinners")
    state = event(state, key(" "))
    state = next_frame(state)
    flush_frames()
    refute_receive {:ascii_art_frame, _, _}, 300
    assert screen(state) =~ "paused"
  end

  test "a key's release or repeat does nothing" do
    state = mount(piece: "spinners")
    assert {:noreply, ^state} = Viewer.handle_event(%Key{code: " ", kind: "release"}, state)
    assert {:noreply, ^state} = Viewer.handle_event(%Key{code: "q", kind: "repeat"}, state)
  end

  test "→ and ← step through its pieces, round from either end" do
    state = mount(pieces: ["spinners", "elixir", "progress-bar"], piece: "progress-bar")
    assert screen(state) =~ "progress bar"

    state = event(state, key("right"))
    assert screen(state) =~ "spinners"
    state = event(state, key("left"))
    assert screen(state) =~ "progress bar"
    state = event(state, key("left"))
    assert screen(state) =~ "elixir"
  end

  test "every piece by default, starting from the one given" do
    state = mount(piece: "donut")
    assert screen(state) =~ "donut"
    [next | _] = AsciiArt.pieces() |> Enum.drop_while(&(&1 != "donut")) |> tl()
    state = event(state, key("right"))
    assert screen(state) =~ AsciiArt.meta!(next).name
  end

  test "a piece that is not among its pieces comes first" do
    state = mount(pieces: ["spinners"], piece: AsciiArt.TestPieces.Blink)
    assert screen(state) =~ "blink"
    state = event(state, key("right"))
    assert screen(state) =~ "spinners"
  end

  test "the piece before stops, and a frame it sent is not shown" do
    state = [pieces: ["spinners", "elixir"], piece: "spinners"] |> mount() |> next_frame()
    [before] = players()
    assert_receive {:ascii_art_frame, _ref, _frame} = stale, 1000

    monitor = Process.monitor(before)
    state = event(state, key("right"))
    assert_receive {:DOWN, ^monitor, :process, ^before, _}, 1000
    assert [now] = players()
    assert now != before

    assert {:noreply, ^state, render?: false} = Viewer.handle_info(stale, state)
  end

  test "its options are the first piece's, whenever it plays" do
    opts = [pieces: ["gauge", "progress-bar"], piece: "gauge", options: %{value: 63}]
    state = opts |> mount() |> next_frame()
    assert screen(state) =~ "63%"

    # The progress bar would refuse a gauge's options.
    state = state |> event(key("right")) |> next_frame()
    assert screen(state) =~ "progress bar"

    state = state |> event(key("left")) |> next_frame()
    assert screen(state) =~ "63%"
  end

  test "q, esc and ctrl-c quit" do
    state = mount(piece: "spinners")

    for event <- [key("q"), key("esc"), key("c", ["ctrl"])] do
      assert {:stop, _} = Viewer.handle_event(event, state)
    end
  end

  test "other keys and events change nothing" do
    state = mount(piece: "spinners")
    assert {:noreply, ^state} = Viewer.handle_event(key("x"), state)
    assert {:noreply, ^state} = Viewer.handle_event(%Resize{width: 20, height: 10}, state)
    assert {:noreply, ^state, render?: false} = Viewer.handle_info(:other, state)
  end

  test "on a screen too small for the piece, its middle" do
    state = [piece: "elixir", pieces: ["elixir"]] |> mount() |> next_frame()
    screen = screen(state, %ExRatatui.Frame{width: 20, height: 10})
    assert screen =~ "8888888888"
  end

  test "in xterm's 256 colours" do
    state = [piece: "elixir", mode: :ansi256] |> mount() |> next_frame()
    colors = for cell <- cells(state, @size), cell.fg != :reset, uniq: true, do: cell.fg
    assert colors != [] and Enum.all?(colors, &match?({:indexed, _}, &1))
  end

  test "a piece or option it does not know is an error" do
    assert {:error, :unknown_piece} = Viewer.mount(piece: "nope")
    assert {:error, :unknown_piece} = Viewer.mount(pieces: ["spinners", "nope"])
    assert {:error, :unknown_piece} = Viewer.mount(pieces: [])
    assert {:error, {:invalid_option, _}} = Viewer.mount(piece: "gauge", options: %{evil: 1})
  end

  test "a player that crashes takes the viewer with it" do
    state = mount(piece: "spinners")
    [player] = players()
    assert catch_exit(Viewer.handle_info({:EXIT, player, :boom}, state)) == :boom
  end

  describe "as an app" do
    # Polls `fun` until it holds: the suite runs alongside this test, so the
    # deadline is generous.
    defp until(fun, deadline \\ System.monotonic_time(:millisecond) + 10_000) do
      cond do
        fun.() ->
          :ok

        System.monotonic_time(:millisecond) > deadline ->
          flunk("timed out")

        true ->
          Process.sleep(20)
          until(fun, deadline)
      end
    end

    test "it plays headlessly, and q stops it" do
      opts = [piece: "spinners", pieces: ["spinners"], test_mode: {60, 20}, name: nil]
      {:ok, pid} = Viewer.start_link(opts)
      ref = Process.monitor(pid)
      until(fn -> Runtime.snapshot(pid).render_count >= 4 end)

      :ok = Runtime.inject_event(pid, key("q"))
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "run/1 refuses a piece or option it does not know, before it starts" do
      assert Viewer.run(piece: "nope", test_mode: {60, 20}) == {:error, :unknown_piece}

      assert {:error, {:invalid_option, _}} =
               Viewer.run(piece: "gauge", options: %{evil: 1}, test_mode: {60, 20})

      assert {:error, {:invalid_option, :fps}} =
               Viewer.run(piece: "gauge", fps: "fast", test_mode: {60, 20})
    end

    test "run/1 returns when it is quit" do
      name = :"viewer_#{System.unique_integer([:positive])}"
      task = Task.async(fn -> Viewer.run(piece: "spinners", test_mode: {60, 20}, name: name) end)
      until(fn -> Process.whereis(name) end)

      :ok = Runtime.inject_event(name, key("q"))
      assert Task.await(task) == :ok
    end
  end
end
