defmodule Ascii.PlayerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ascii.{Frame, Player}
  alias Ascii.TestPieces.{Blink, Counted, Gated}

  test "sends frames to the caller, tagged with its ref, play time rising" do
    {:ok, pid} = Player.start_link(piece: "donut", fps: 50)
    ref = Player.ref(pid)
    assert_receive {:ascii_frame, ^ref, %Frame{t: +0.0, rows: 22}}, 500
    assert_receive {:ascii_frame, ^ref, %Frame{t: t1}}, 500
    assert_receive {:ascii_frame, ^ref, %Frame{t: t2}}, 500
    assert 0 < t1 and t1 < t2
    Player.stop(pid)
  end

  test "in ink, checked as Ascii.new/2 checks it" do
    {:ok, pid} = Player.start_link(piece: Blink, ink: "#ff8800")
    ref = Player.ref(pid)
    assert_receive {:ascii_frame, ^ref, %Frame{palette: ["#ff8800"], text: " * "}}, 500
    Player.stop(pid)
    assert Player.start_link(piece: Blink, ink: "red") == {:error, {:invalid_option, :ink}}
  end

  test "colours for parts, checked as Ascii.new/2 checks them" do
    {:ok, pid} = Player.start_link(piece: "file-tree", parts: %{folder: "#58a6ff"})
    ref = Player.ref(pid)
    assert_receive {:ascii_frame, ^ref, %Frame{palette: [nil, "#58a6ff"]}}, 1000
    Player.stop(pid)

    assert Player.start_link(piece: "file-tree", parts: %{evil: "#fff"}) ==
             {:error, {:invalid_option, {:parts, :evil}}}
  end

  test "a callback instead of messages" do
    test = self()

    {:ok, pid} =
      Player.start_link(piece: "spinners", fps: 50, callback: &send(test, {:called, &1.t}))

    assert_receive {:called, +0.0}, 500
    assert_receive {:called, t} when t > 0, 500
    Player.stop(pid)
  end

  test "pause holds, and paused time does not count, as upstream's mount" do
    {:ok, pid} = Player.start_link(piece: "donut", fps: 50, ref: :donut)
    assert_receive {:ascii_frame, :donut, %Frame{t: t0}}, 1000
    :ok = Player.pause(pid)
    paused_at = flush(t0)
    Process.sleep(300)
    refute_received {:ascii_frame, :donut, _}
    :ok = Player.resume(pid)
    assert_receive {:ascii_frame, :donut, %Frame{t: t}}, 1000
    # A tick's step is capped at 100 ms, and the 300 ms pause is not a step.
    assert t > paused_at and t - paused_at <= 0.1 + 1.0e-9
    Player.stop(pid)
  end

  test "set_fps changes the pace; 0 holds the picture" do
    {:ok, pid} = Player.start_link(piece: "donut", fps: 5, ref: :slow)
    assert_receive {:ascii_frame, :slow, _}, 500
    :ok = Player.set_fps(pid, 60)
    # Each within 150 ms, where at 5 fps a frame takes 200.
    assert_receive {:ascii_frame, :slow, _}, 150
    assert_receive {:ascii_frame, :slow, _}, 150
    :ok = Player.set_fps(pid, 0)
    flush(0)
    Process.sleep(150)
    refute_received {:ascii_frame, :slow, _}
    assert Player.set_fps(pid, 99) == {:error, {:invalid_option, :fps}}
    Player.stop(pid)
  end

  test "a still piece sends one frame" do
    still = Enum.find(Ascii.pieces(), &(Ascii.meta!(&1).fps == 0))

    if still do
      {:ok, pid} = Player.start_link(piece: still, ref: :still)
      assert_receive {:ascii_frame, :still, _}, 500
      refute_receive {:ascii_frame, :still, _}, 150
      Player.stop(pid)
    end
  end

  test "stops when its owner goes" do
    Process.flag(:trap_exit, true)
    test = self()

    subscriber =
      spawn(fn ->
        {:ok, pid} = Player.start(piece: "donut", fps: 50)
        send(test, {:player, pid})

        receive do
          :go -> :ok
        end
      end)

    assert_receive {:player, pid}, 2000
    ref = Process.monitor(pid)
    send(subscriber, :go)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end

  test "an unknown piece or option fails to start, without an exit to trap" do
    assert Player.start_link(piece: "nope") == {:error, :unknown_piece}

    assert Player.start_link(piece: "donut", options: %{"x" => 1}) ==
             {:error, {:invalid_option, "x"}}

    assert Player.start_link(options: %{}) == {:error, {:invalid_option, :piece}}
  end

  test "plays a piece module of our own" do
    {:ok, pid} = Player.start_link(piece: Blink, options: %{dot: "o"}, ref: :blink)
    assert_receive {:ascii_frame, :blink, %Frame{text: " o ", t: +0.0}}, 500
    Player.stop(pid)
  end

  test "returns before the piece is set up, and sets it up before anything else" do
    # Gated's setup waits for :go, which only comes once start_link returns.
    {:ok, pid} = Player.start_link(piece: Gated)
    waiting = Task.async(fn -> Player.frame(pid) end)
    refute Task.yield(waiting, 100)
    send(pid, :go)
    assert %Frame{text: "g", t: +0.0} = Task.await(waiting)
    Player.stop(pid)
  end

  test "frame/1 is the latest frame drawn" do
    {:ok, pid} = Player.start_link(piece: "donut", fps: 50, ref: :latest)
    assert_receive {:ascii_frame, :latest, _}, 500
    assert_receive {:ascii_frame, :latest, %Frame{t: t}}, 500
    assert Player.frame(pid).t >= t
    Player.stop(pid)
  end

  test "set_options/2 changes a playing piece's options, and draws it at once" do
    {:ok, pid} = Player.start_link(piece: Ascii.TestPieces.Bar, fps: 0, ref: :bar)
    assert_receive {:ascii_frame, :bar, %Frame{text: ".........."}}, 500
    assert Player.set_options(pid, value: 50, width: 4) == :ok
    assert_receive {:ascii_frame, :bar, %Frame{text: "##..", cols: 4}}, 500
    assert Player.frame(pid).text == "##.."
    assert Player.set_options(pid, evil: 1) == {:error, {:invalid_option, :evil}}
    Player.stop(pid)
  end

  describe "a piece that closes a loop" do
    # Frames that arrive within `ms`, and how many times the piece was drawn.
    defp watch(ms) do
      Process.sleep(ms)

      frames =
        Stream.repeatedly(fn ->
          receive(do: ({:ascii_frame, _, f} -> f), after: (0 -> nil))
        end)

      frames = frames |> Enum.take_while(& &1) |> Enum.to_list()
      drawn = Stream.repeatedly(fn -> receive(do: ({:drawn, _} -> 1), after: (0 -> nil)) end)
      {frames, drawn |> Enum.take_while(& &1) |> length()}
    end

    test "is drawn once a frame of its cycle, then replayed" do
      Process.register(self(), :loop_watch)
      {:ok, pid} = Player.start_link(piece: Counted)
      {frames, drawn} = watch(1600)
      Player.stop(pid)

      # Three cycles and more, of ten frames each, drawn at most ten times.
      assert length(frames) > 25
      assert drawn <= 10
      # Each frame as at its place in the cycle, play time still rising.
      assert Enum.all?(
               frames,
               &(&1.text == Integer.to_string(rem(floor(&1.t * 20 + 1.0e-9), 10)))
             )

      ts = Enum.map(frames, & &1.t)
      assert ts == Enum.sort(ts) and List.last(ts) > 1.0
    end

    test "is drawn every time with cache: false, or at a rate it was not measured at" do
      Process.register(self(), :loop_watch)

      for opts <- [[cache: false], [fps: 10]] do
        {:ok, pid} = Player.start_link([piece: Counted] ++ opts)
        {frames, drawn} = watch(700)
        Player.stop(pid)
        assert drawn >= length(frames) and length(frames) > 5
      end
    end
  end

  describe "under a supervisor" do
    test "it sends nothing to the supervisor; processes subscribe instead" do
      log =
        capture_log(fn ->
          pid = start_supervised!({Player, piece: "spinners", fps: 50})
          :ok = Player.subscribe(pid)
          ref = Player.ref(pid)
          assert_receive {:ascii_frame, ^ref, %Frame{}}, 500
          assert_receive {:ascii_frame, ^ref, %Frame{t: t}} when t > 0, 500
          Process.sleep(100)
        end)

      refute log =~ "unexpected"
    end

    test "with no one to send to, it holds its frame and does no work" do
      pid = start_supervised!({Player, piece: "donut", fps: 50})
      Process.sleep(100)
      assert Player.frame(pid).t == 0.0

      test = self()

      # A viewer that passes on the first frame it gets after frame 0.
      viewer =
        spawn(fn ->
          :ok = Player.subscribe(pid)

          receive do
            {:ascii_frame, _, %Frame{t: t}} when t > 0 -> send(test, {:playing, t})
          end

          Process.sleep(:infinity)
        end)

      assert_receive {:playing, _t}, 2000

      ref = Process.monitor(viewer)
      Process.exit(viewer, :kill)
      assert_receive {:DOWN, ^ref, :process, ^viewer, :killed}, 2000
      # Time for the player to take its own word of the viewer's exit.
      Process.sleep(50)
      held = Player.frame(pid).t
      Process.sleep(100)
      assert Player.frame(pid).t == held
      assert Process.alive?(pid)
    end

    test "unsubscribe stops the frames" do
      pid = start_supervised!({Player, piece: "donut", fps: 50, ref: :unsub})
      :ok = Player.subscribe(pid)
      assert_receive {:ascii_frame, :unsub, _}, 500
      :ok = Player.unsubscribe(pid)
      flush(0)
      Process.sleep(100)
      refute_received {:ascii_frame, :unsub, _}
    end

    test "a callback still gets every frame" do
      test = self()

      start_supervised!(
        {Player, piece: "spinners", fps: 50, callback: &send(test, {:called, &1.t})}
      )

      assert_receive {:called, +0.0}, 500
      assert_receive {:called, t} when t > 0, 500
    end

    test "its child id is its name, so a supervisor can hold several" do
      assert Player.child_spec(piece: "donut", name: :a).id == :a
      assert Player.child_spec(piece: "donut").id == Player

      start_supervised!({Player, piece: "donut", name: :donut_player})
      start_supervised!({Player, piece: "spinners", name: :spinners_player})
      assert Player.frame(:spinners_player).rows == 13
    end
  end

  test "an owner who also subscribes gets each frame once" do
    {:ok, pid} = Player.start_link(piece: "donut", fps: 50, ref: :once)
    :ok = Player.subscribe(pid)
    assert_receive {:ascii_frame, :once, %Frame{t: t}} when t > 0, 500
    refute_received {:ascii_frame, :once, %Frame{t: ^t}}
    Player.stop(pid)
  end

  # Drains frame messages, returning the latest play time seen.
  defp flush(t) do
    receive do
      {:ascii_frame, _, %Frame{t: t}} -> flush(t)
    after
      0 -> t
    end
  end
end
