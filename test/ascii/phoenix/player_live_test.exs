defmodule Ascii.Phoenix.PlayerLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ascii.Phoenix.PlayerLive
  alias Ascii.TestPieces.{Blink, Static}

  @endpoint Ascii.Test.Endpoint

  defp mount(session), do: live_isolated(build_conn(), PlayerLive, session: session)

  # The player's events are named for it, so two on a page keep apart.
  defp event(view), do: "ascii:" <> view.id

  # Ticks, a little over 100 ms apart, until play time passes half a second.
  defp play_past_half_a_second(view) do
    for _ <- 1..6 do
      Process.sleep(110)
      send(view.pid, :tick)
    end

    render(view)
  end

  # refute_push_event/4 takes no pinned event name.
  defp refute_event(view, ev, timeout) do
    %{proxy: {ref, _topic, _}} = view
    refute_receive {^ref, {:push_event, ^ev, _}}, timeout
  end

  # A hook says it is there, on screen, and can inflate.
  defp ready(view, deflate \\ true),
    do: render_hook(view, "ascii:ready", %{"visible" => true, "deflate" => deflate})

  defp dead(session) do
    {:ok, socket} = PlayerLive.mount(%{}, session, %Phoenix.LiveView.Socket{id: "phx-dead"})
    socket.assigns |> PlayerLive.render() |> rendered_to_string()
  end

  # What a loop event holds, made into frames again as the hook does: the
  # runs of cells that changed from the frame before, or an earlier frame's
  # index.
  defp unpack(%{deflate: packed}),
    do: packed |> Base.decode64!() |> :zlib.uncompress() |> JSON.decode!() |> unpack()

  defp unpack(%{fps: fps, frames: frames}),
    do: unpack(%{"fps" => fps, "frames" => frames |> JSON.encode!() |> JSON.decode!()})

  defp unpack(%{"fps" => fps, "frames" => [first | rest]}) do
    frames =
      Enum.reduce(rest, [apply_rows(%{}, first)], fn
        j, done when is_integer(j) -> [done |> Enum.reverse() |> Enum.at(j) | done]
        rows, [prev | _] = done -> [apply_rows(prev, rows) | done]
      end)

    {Enum.reverse(frames), fps}
  end

  defp apply_rows(frame, runs) do
    Enum.reduce(runs, frame, fn [y, x, text, colors], acc ->
      {line, row} = Map.get(acc, y, {"", nil})
      n = String.length(text)
      line = String.slice(line, 0, x) <> text <> String.slice(line, (x + n)..-1//1)
      row = colors && splice(row, x, Base.decode64!(colors))
      Map.put(acc, y, {line, row})
    end)
  end

  defp splice(nil, 0, bytes), do: bytes

  defp splice(row, x, bytes),
    do:
      binary_part(row, 0, x) <>
        bytes <> binary_part(row, x + byte_size(bytes), byte_size(row) - x - byte_size(bytes))

  defp rows_of(%Ascii.Frame{} = f) do
    for {line, y} <- Enum.with_index(f.lines), into: %{} do
      {y, {line, f.colors && binary_part(f.colors, y * f.cols, f.cols)}}
    end
  end

  # The diffs LiveView sends the test's client from now on, read through its
  # proxy process; the function returns those that came since it was made.
  defp watch_diffs(view) do
    {_ref, _topic, proxy} = view.proxy
    :erlang.trace(proxy, true, [:receive])

    fn ->
      render(view)

      fn ->
        receive do
          {:trace, ^proxy, :receive, %Phoenix.Socket.Message{event: "diff", payload: diff}} ->
            diff

          {:trace, ^proxy, :receive, _other} ->
            :other
        after
          100 -> :done
        end
      end
      |> Stream.repeatedly()
      |> Enum.take_while(&(&1 != :done))
      |> Enum.reject(&(&1 == :other))
    end
  end

  describe "before it connects" do
    test "it is frame 0, whole, as HTML, in either mode" do
      for render <- ["client", "server"] do
        html = dead(%{"piece" => "night-coast", "render" => render})
        assert html =~ ~s(role="img")
        assert html =~ ~s(<span style="color:#)
        refute html =~ "<canvas"
      end

      line = Ascii.render!("donut") |> String.split("\n") |> Enum.at(10)
      assert dead(%{"piece" => "donut"}) =~ line
    end

    test "the piece is not set up for it: frame 0 is kept from the first time" do
      Process.put(:init_watch, true)
      dead(%{"piece" => Ascii.TestPieces.Noted})
      html = dead(%{"piece" => Ascii.TestPieces.Noted})
      assert html =~ "#0"
      inits = Stream.repeatedly(fn -> receive(do: (:init -> 1), after: (0 -> nil)) end)
      assert inits |> Enum.take_while(& &1) |> length() <= 1
    end

    test "in the browser's mode, it carries what the hook needs to draw" do
      html = dead(%{"piece" => "elixir"})
      assert html =~ ~s(phx-hook="Ascii")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(data-palette=)
      assert html =~ ~s(data-colors=)
      assert html =~ ~s(data-event="ascii:phx-dead")
    end
  end

  describe "in the browser" do
    test "nothing is drawn or sent until the hook says it is there" do
      {:ok, view, _} = mount(%{"piece" => "donut", "fps" => 60})
      ev = event(view)
      send(view.pid, :tick)
      refute_event(view, ev, 100)
    end

    test "a loop is sent once, and is the piece's cycle" do
      {:ok, view, _} = mount(%{"piece" => "elixir"})
      ev = event(view)
      ready(view)
      assert_push_event(view, ^ev, %{loop: %{deflate: _, t: t} = loop}, 2000)
      assert is_float(t)

      {:ok, frames, 30} = Ascii.new!("elixir") |> Ascii.loop()
      assert unpack(loop) == {Enum.map(frames, &rows_of/1), 30}

      # The server's part is over.
      send(view.pid, :tick)
      refute_event(view, ev, 200)
    end

    test "without inflate in the browser, the loop is sent as it is" do
      {:ok, view, _} = mount(%{"piece" => "owl"})
      ev = event(view)
      ready(view, false)
      assert_push_event(view, ^ev, %{loop: %{fps: 12, frames: _} = loop}, 2000)
      {:ok, frames, 12} = Ascii.new!("owl") |> Ascii.loop()
      assert unpack(loop) == {Enum.map(frames, &rows_of/1), 12}
    end

    test "a loop too big to send is played frame by frame" do
      {:ok, view, _} = mount(%{"piece" => Static})
      ev = event(view)
      ready(view)
      render_async(view, 5000)
      %{proxy: {ref, _, _}} = view
      refute_received {^ref, {:push_event, ^ev, %{loop: _}}}
      assert_push_event(view, ^ev, %{runs: [_ | _]}, 1000)
    end

    test "any other piece sends the cells that changed, and nothing when none did" do
      # fps 0: only this test's ticks draw. Blink shows " * " for its first
      # half second, then "   ".
      {:ok, view, _} = mount(%{"piece" => Blink, "fps" => 0})
      ev = event(view)
      ready(view)
      send(view.pid, :tick)
      refute_event(view, ev, 100)
      # Play time moves at most 100 ms a tick, as upstream's.
      play_past_half_a_second(view)
      # The dot, the one cell that changed.
      assert_push_event(view, ^ev, %{runs: [[0, 1, " ", nil]]})
      refute_event(view, ev, 0)
    end

    test "the hook stops and starts the ticks as the picture leaves and comes into view" do
      {:ok, view, _} = mount(%{"piece" => "donut", "fps" => 0})
      ev = event(view)
      ready(view)
      render_hook(view, "ascii:visible", %{"visible" => false})
      send(view.pid, :tick)
      refute_event(view, ev, 100)
      render_hook(view, "ascii:visible", %{"visible" => true})
      Process.sleep(50)
      send(view.pid, :tick)
      assert_push_event(view, ^ev, %{runs: [_ | _]})
    end

    test "with no hook to answer, it draws on the server" do
      {:ok, view, _} = mount(%{"piece" => "donut", "fps" => 30})
      send(view.pid, :no_hook)
      html = render(view)
      refute html =~ "phx-hook"
      Process.sleep(100)
      refute render(view) == html
    end
  end

  describe "on the server" do
    test "it plays, each tick patching the picture" do
      {:ok, view, html} = mount(%{"piece" => "donut", "render" => "server", "fps" => "30"})
      refute html =~ "phx-hook"
      send(view.pid, :tick)
      Process.sleep(20)
      send(view.pid, :tick)
      refute render(view) == html
    end

    test "LiveView sends the rows that changed, and nothing when none did" do
      {:ok, view, _} = mount(%{"piece" => Blink, "render" => "server", "fps" => 0})
      diffs = watch_diffs(view)
      send(view.pid, :tick)
      assert diffs.() == []
      play_past_half_a_second(view)
      assert [diff] = diffs.()
      # One row, of one: "   ".
      assert inspect(diff) =~ ~s("   ")
      refute inspect(diff) =~ "*"
    end

    test "a coloured piece is spans of its palette" do
      {:ok, view, _} = mount(%{"piece" => "elixir", "render" => "server"})
      assert render(view) =~ ~s(<span style="color:#)
    end
  end

  test "session keys are whitelisted, options checked, values cast" do
    {:ok, view, _} =
      mount(%{"piece" => "typewriter", "options" => %{"prefix" => "we make "}, "evil" => "x"})

    assert render(view) =~ "we make "

    {:ok, view, _} = mount(%{"piece" => "typewriter", "options" => %{"evil" => 1}})
    assert render(view) =~ "invalid option"

    {:ok, view, _} = mount(%{"piece" => "no-such-piece"})
    assert render(view) =~ "unknown piece"
  end

  test "mono and paper" do
    {:ok, view, _} = mount(%{"piece" => "elixir", "mono" => "true", "paper" => true})
    refute render(view) =~ "<span"
  end

  test "ink, and which way it runs" do
    html = dead(%{"piece" => "big-text", "ink" => "#ff5f6d,#ffc371", "gradient" => "vertical"})
    assert html =~ ~s(data-palette=)
    refute html =~ ~s(data-ground=)

    {:ok, view, _} = mount(%{"piece" => "big-text", "ink" => "#ff8800", "render" => "server"})
    assert render(view) =~ ~s(<span style="color:#ff8800">)

    {:ok, view, _} = mount(%{"piece" => "big-text", "ink" => "red"})
    assert render(view) =~ "invalid option :ink"
  end

  test "a piece in an ink is drawn as text in spans; a coloured piece, on a canvas" do
    assert dead(%{"piece" => "big-text", "ink" => "#ff8800"}) =~ ~s(data-spans="true")
    assert dead(%{"piece" => "boot-log", "parts" => true}) =~ ~s(data-spans="true")

    assert dead(%{"piece" => "elixir", "mono" => true, "ink" => "#ff8800"}) =~
             ~s(data-spans="true")

    refute dead(%{"piece" => "elixir"}) =~ "data-spans"
    refute dead(%{"piece" => "donut"}) =~ "data-spans"
  end

  test "parts, from the session" do
    {:ok, view, _} =
      mount(%{
        "piece" => "boot-log",
        "parts" => %{"status.warn" => "#d29922"},
        "render" => "server"
      })

    assert render(view) =~ ~s(<span style="color:#d29922">[ WARN ])

    html = dead(%{"piece" => "boot-log", "parts" => true})
    assert html =~ ~s(data-palette="[null,)

    {:ok, view, _} = mount(%{"piece" => "boot-log", "parts" => %{"evil" => "#fff"}})
    assert render(view) =~ ~s(invalid option {:parts, &quot;evil&quot;})
  end

  test "an unknown render mode is the default" do
    {:ok, view, _} = mount(%{"piece" => "elixir", "render" => "evil"})
    assert render(view) =~ ~s(phx-hook="Ascii")
  end

  test "a piece module of our own, given in the session by the server" do
    {:ok, view, html} = mount(%{"piece" => Blink, "options" => %{"dot" => "o"}})
    assert html =~ " o "
    assert render(view) =~ ~s(aria-label="blink: a dot that blinks")
  end

  test "a module named by a string is not a piece: strings are slugs" do
    {:ok, view, _} = mount(%{"piece" => "Ascii.TestPieces.Blink"})
    assert render(view) =~ "unknown piece"

    {:ok, view, _} = mount(%{"piece" => "Elixir.Ascii.TestPieces.Blink"})
    assert render(view) =~ "unknown piece"
  end

  test "an atom that is not a piece module is an unknown piece" do
    for piece <- [Enum, nil, true, :nope] do
      {:ok, view, _} = mount(%{"piece" => piece})
      assert render(view) =~ "unknown piece"
    end
  end

  describe "Ascii.Phoenix.player/1" do
    defmodule Host do
      use Phoenix.LiveView

      def render(assigns) do
        ~H"""
        <Ascii.Phoenix.player socket={@socket} id="art" piece="spinners" fps={12} label="loading" />
        <Ascii.Phoenix.player socket={@socket} id="own" piece={Ascii.TestPieces.Blink} render={:server} />
        <Ascii.Phoenix.player socket={@socket} id="inked" piece={Ascii.TestPieces.Blink} render={:server} ink="#ff8800" gradient={:vertical} />
        """
      end
    end

    test "embeds players with live_render, each with its own events" do
      {:ok, view, html} = live_isolated(build_conn(), Host)
      assert html =~ ~s(aria-label="loading")
      art = find_live_child(view, "art")
      own = find_live_child(view, "own")
      assert render(art) =~ ~s(data-event="#{event(art)}")
      assert render(own) =~ " * "
      refute event(art) == event(own)
      assert render(find_live_child(view, "inked")) =~ ~s(<span style="color:#ff8800">)
    end

    defmodule Listener do
      use Phoenix.LiveView

      def mount(_params, session, socket), do: {:ok, assign(socket, test: session["test"])}

      def handle_info({:ascii, _id, _info} = told, socket) do
        send(socket.assigns.test, told)
        {:noreply, socket}
      end

      def render(assigns) do
        ~H"""
        <Ascii.Phoenix.player socket={@socket} id="sw" piece={Ascii.TestPieces.Switches} render={:server} interactive notify />
        """
      end
    end

    test "an interactive player tells the LiveView that embeds it of each key and click" do
      {:ok, view, _html} = live_isolated(build_conn(), Listener, session: %{"test" => self()})
      player = find_live_child(view, "sw")
      player |> element("pre") |> render_keydown(%{"key" => " "})

      assert_receive {:ascii, "sw", %{event: {:key, " "}, options: %{on: [true, true, false]}}}

      assert render(player) =~ "&gt;[x]  [x]  [ ]"
    end
  end
end
