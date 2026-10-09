defmodule AsciiArt.Phoenix.PlayerComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint AsciiArt.Test.Endpoint

  # A LiveView of yours: the piece's options come from its assigns, which
  # {:set, assigns} changes, as new data would.
  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         piece: session["piece"] || "gauge",
         options: session["options"] || %{value: 40},
         render: session["render"] || :client,
         ink: session["ink"],
         parts: session["parts"],
         interactive: session["interactive"] == true,
         notify: session["notify"] == true,
         test: session["test"],
         other: 0
       )}
    end

    def handle_info({:set, assigns}, socket), do: {:noreply, assign(socket, assigns)}

    # What the player tells us of its keys and clicks, passed on to the test.
    def handle_info({:ascii_art, _id, _info} = told, socket) do
      send(socket.assigns.test, told)
      {:noreply, socket}
    end

    def render(assigns) do
      ~H"""
      <div>
        <AsciiArt.Phoenix.live_player
          id="w"
          piece={@piece}
          options={@options}
          render={@render}
          ink={@ink}
          parts={@parts}
          interactive={@interactive}
          notify={@notify}
        />
        <span id="other">{@other}</span>
      </div>
      """
    end
  end

  defp host(session \\ %{}), do: live_isolated(build_conn(), Host, session: session)

  defp set(view, assigns) do
    send(view.pid, {:set, assigns})
    render(view)
  end

  # The hook says it is there, from its element, so to the component.
  defp ready(view, gen \\ 1) do
    view
    |> element("#ascii-art-w-#{gen}-art")
    |> render_hook("ascii_art:ready", %{"visible" => true, "deflate" => false})
  end

  # Changes pushed until one has `text` in it: a tick before the change
  # may have pushed some first.
  defp assert_runs_with(view, ev, text) do
    assert_push_event(view, ^ev, %{runs: runs}, 1000)

    if not Enum.any?(runs, fn [_y, _x, run, _] -> run =~ text end),
      do: assert_runs_with(view, ev, text)
  end

  defp refute_event(view, ev, timeout) do
    %{proxy: {ref, _topic, _}} = view
    refute_receive {^ref, {:push_event, ^ev, _}}, timeout
  end

  test "before it connects, frame 0 with the options given" do
    {:ok, _view, html} = host(%{"options" => %{value: 63}})
    assert html =~ "63%"
    assert html =~ ~s(phx-hook="AsciiArt")
    assert html =~ ~s(phx-target=)
  end

  test "on the server, new options are drawn at once" do
    {:ok, view, _} = host(%{"render" => :server})
    assert set(view, options: %{value: 85}) =~ "85%"
  end

  test "in the browser, the hook's events reach the component, and new options are sent as changes" do
    {:ok, view, _} = host()
    ready(view)
    ev = "ascii_art:ascii-art-w-1"
    set(view, options: %{value: 85})

    # The size is the same, so no whole picture: the next tick sends what
    # changed, the readout's new digits among it.
    assert_runs_with(view, ev, "85")
    %{proxy: {ref, _topic, _}} = view
    refute_received {^ref, {:push_event, ^ev, %{frame: _}}}
  end

  test "options that change the size send the whole picture at its new size" do
    {:ok, view, _} = host(%{"piece" => "progress-bar", "options" => %{values: [10]}})
    ready(view)
    ev = "ascii_art:ascii-art-w-1"
    set(view, options: %{values: [10, 20, 30]})
    assert_push_event(view, ^ev, %{frame: %{cols: 48, rows: 7, runs: runs}}, 1000)
    assert length(runs) == 7
  end

  test "a loop playing in the browser gives way to new options, and a new cycle follows" do
    {:ok, view, _} = host(%{"piece" => "elixir", "options" => %{}})
    ready(view)
    ev = "ascii_art:ascii-art-w-1"
    assert_push_event(view, ^ev, %{loop: %{fps: 30}}, 2000)

    set(view, options: %{shine: 2.5})
    assert_push_event(view, ^ev, %{frame: %{cols: 38, rows: 28}}, 1000)
    assert_push_event(view, ^ev, %{loop: %{fps: 30}}, 2000)
  end

  test "the same options rendered again change nothing" do
    {:ok, view, _} = host(%{"piece" => "progress-bar", "options" => %{values: [50]}})
    ready(view)
    ev = "ascii_art:ascii-art-w-1"
    set(view, other: 1)
    set(view, options: %{values: [50]})
    refute_event(view, ev, 200)
  end

  test "another piece starts afresh, under a new id" do
    {:ok, view, _} = host()
    html = set(view, piece: "spinners", options: %{})
    assert html =~ ~s(id="ascii-art-w-2-art")
    refute html =~ "ascii-art-w-1-art"
  end

  test "with no hook to answer, it draws on the server, and still takes new options" do
    {:ok, view, _} = host()
    message = [id: "w", ascii_art: :no_hook, gen: 1]
    Phoenix.LiveView.send_update(view.pid, AsciiArt.Phoenix.PlayerComponent, message)
    refute render(view) =~ "phx-hook"
    assert set(view, options: %{value: 77}) =~ "77%"
  end

  test "a message from before it last started afresh is ignored" do
    {:ok, view, _} = host()
    message = [id: "w", ascii_art: :no_hook, gen: 0]
    Phoenix.LiveView.send_update(view.pid, AsciiArt.Phoenix.PlayerComponent, message)
    assert render(view) =~ "phx-hook"
  end

  # LiveViewTest routes a hook's events by the element's phx-target, which a
  # browser does not: there a hook's pushEvent always goes to the LiveView,
  # and only pushEventTo(this.el) reaches the component the element is in.
  test "the hook sends its events to whatever owns its element" do
    hook = File.read!("priv/static/ascii_art_hook.js")
    assert hook =~ ~s[this.pushEventTo(this.el, "ascii_art:ready"]
    assert hook =~ ~s[this.pushEventTo(this.el, "ascii_art:visible"]
    refute hook =~ "this.pushEvent("
  end

  test "an ink colours it, and another starts it afresh" do
    {:ok, view, _} = host(%{"render" => :server, "ink" => "#ff8800"})
    assert render(view) =~ ~s(<span style="color:#ff8800">)
    html = set(view, ink: "#00ff88")
    assert html =~ ~s(<span style="color:#00ff88">)
    assert html =~ ~s(id="ascii-art-w-2-art-pre")
  end

  test "colours for parts, and others start it afresh" do
    {:ok, view, _} =
      host(%{"render" => :server, "piece" => "boot-log", "options" => %{}, "parts" => true})

    assert render(view) =~ ~s(<span style="color:#3fb950">[  OK  ])
    html = set(view, parts: %{"status.ok" => "#ff0000"})
    assert html =~ ~s(<span style="color:#ff0000">[  OK  ])
    assert html =~ ~s(id="ascii-art-w-2-art-pre")
  end

  test "options it refuses show why" do
    {:ok, view, _} = host()
    assert set(view, options: %{evil: 1}) =~ "invalid option"
  end

  describe "keys and clicks" do
    alias AsciiArt.TestPieces.Switches

    defp switches(session),
      do: host(Map.merge(%{"piece" => Switches, "options" => %{}, "test" => self()}, session))

    defp hook(view, event, params),
      do: view |> element("#ascii-art-w-1-art") |> render_hook(event, params)

    test "an interactive player takes focus, and is labelled with what the piece tells" do
      {:ok, _view, html} = switches(%{"interactive" => true})
      assert html =~ ~s(role="application")
      assert html =~ ~s(tabindex="0")
      assert html =~ ~s(data-interactive="true")
      assert html =~ ~s(aria-label="switches: 1 of 3 on")
    end

    test "keys reach the piece by their names, and what changed is sent at once" do
      {:ok, view, _} = switches(%{"interactive" => true})
      ready(view)
      hook(view, "ascii_art:key", %{"key" => "ArrowRight"})
      assert_runs_with(view, "ascii_art:ascii-art-w-1", ">")
      hook(view, "ascii_art:key", %{"key" => " "})
      assert_push_event(view, "ascii_art:ascii-art-w-1", %{label: "switches: 0 of 3 on"}, 1000)
    end

    test "a click on a cell, and the LiveView told what was clicked, if it asked" do
      {:ok, view, _} = switches(%{"interactive" => true, "notify" => true})
      ready(view)
      hook(view, "ascii_art:click", %{"x" => 12, "y" => 0})

      assert_receive {:ascii_art, "w",
                      %{event: {:click, 12, 0}, part: "switch", text: "[ ]", options: options}}

      assert options == %{on: [false, true, true], cursor: 2}

      hook(view, "ascii_art:key", %{"key" => "q"})
      assert_receive {:ascii_art, "w", %{event: {:key, "q"}, part: nil, options: ^options}}
    end

    test "shift and tab is back_tab; keys held with ctrl or meta are the browser's" do
      {:ok, view, _} = switches(%{"interactive" => true, "notify" => true})
      ready(view)
      hook(view, "ascii_art:key", %{"key" => "Tab", "shiftKey" => true})
      assert_receive {:ascii_art, "w", %{event: {:key, "back_tab"}}}
      hook(view, "ascii_art:key", %{"key" => "r", "metaKey" => true})
      hook(view, "ascii_art:key", %{"key" => "Shift"})
      refute_receive {:ascii_art, "w", _}, 100
    end

    test "a player that is not interactive takes no keys, and tells nothing" do
      {:ok, view, html} = switches(%{"notify" => true})
      refute html =~ "tabindex"
      ready(view)
      hook(view, "ascii_art:key", %{"key" => "ArrowRight"})
      hook(view, "ascii_art:click", %{"x" => 12, "y" => 0})
      refute_receive {:ascii_art, "w", _}, 100
    end

    test "on the server, keys come by phx-keydown and the picture is patched" do
      {:ok, view, html} = switches(%{"interactive" => true, "render" => :server})
      assert html =~ ~s(phx-keydown="ascii_art:key")
      pre = element(view, "#ascii-art-w-1-art-pre")
      render_keydown(pre, %{"key" => "ArrowRight"})
      assert render_keydown(pre, %{"key" => " "}) =~ " [ ] &gt;[ ]  [ ]"
      assert render(view) =~ ~s(aria-label="switches: 0 of 3 on")
    end
  end
end
