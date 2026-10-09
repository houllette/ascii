defmodule AsciiArtTest do
  use ExUnit.Case, async: true

  doctest AsciiArt

  alias AsciiArt.{Animation, Frame, Meta}

  test "upstream_commit is the pinned commit" do
    assert AsciiArt.upstream_commit() == "fcb644403bfc25af0002e415d1006dd10b99ca34"
    assert File.read!("UPSTREAM.md") =~ AsciiArt.upstream_commit()
  end

  describe "pieces/1" do
    test "lists slugs, sorted, and filters by category" do
      slugs = AsciiArt.pieces()
      assert "donut" in slugs
      assert slugs == Enum.sort(slugs)
      scenes = AsciiArt.pieces(category: :scenes)
      assert "night-coast" in scenes
      refute "donut" in scenes
      assert AsciiArt.pieces(category: :nothing) == []
    end
  end

  describe "meta/1" do
    test "by slug or module" do
      assert {:ok, %Meta{name: "donut", cols: 40, rows: 22}} = AsciiArt.meta("donut")
      assert AsciiArt.meta(AsciiArt.Pieces.Donut) == AsciiArt.meta("donut")
    end

    test "unknown pieces are errors, not atoms" do
      assert AsciiArt.meta("no-such-piece") == {:error, :unknown_piece}
      assert AsciiArt.meta(String) == {:error, :unknown_piece}
      assert AsciiArt.meta(42) == {:error, :unknown_piece}
      assert_raise ArgumentError, fn -> AsciiArt.meta!("no-such-piece") end
    end
  end

  describe "new/2 and frame/3" do
    test "plays a piece, threading its state" do
      {:ok, anim} = AsciiArt.new("donut")
      assert %Animation{fps: 30, paper: false} = anim
      {%Frame{} = f0, anim} = AsciiArt.frame(anim, 0)
      {f1, _anim} = AsciiArt.frame(anim, 0.5)
      assert f0.t == 0.0 and f1.t == 0.5
      assert length(f0.lines) == 22
      assert Enum.all?(f0.lines, &(String.length(&1) == 40))
      assert f0.text != f1.text
      assert f0.colors == nil
    end

    test "a coloured piece gives colours unless color: false" do
      {:ok, anim} = AsciiArt.new("night-coast")
      {frame, _} = AsciiArt.frame(anim, 0)
      assert byte_size(frame.colors) == 200 * 100
      assert frame.palette == AsciiArt.meta!("night-coast").palette
      assert frame.ground == "#080b12"
      assert frame.cell == 1

      {:ok, mono} = AsciiArt.new("night-coast", color: false)
      {frame, _} = AsciiArt.frame(mono, 0)
      assert frame.colors == nil and frame.palette == nil
    end

    test "paper follows a dark ground in colour, as upstream's mount" do
      assert {:ok, %Animation{paper: false}} = AsciiArt.new("night-coast", paper: true)

      assert {:ok, %Animation{paper: true}} =
               AsciiArt.new("night-coast", paper: true, color: false)

      assert {:ok, %Animation{paper: true}} = AsciiArt.new("donut", paper: true)
    end

    test "options are checked" do
      assert {:ok, %Animation{options: %{prefix: "we make "}}} =
               AsciiArt.new("typewriter", options: %{"prefix" => "we make "})

      assert AsciiArt.new("typewriter", options: %{"evil" => 1}) ==
               {:error, {:invalid_option, "evil"}}

      assert AsciiArt.new("donut", fps: "x") == {:error, {:invalid_option, :fps}}
      assert {:ok, %Animation{fps: 60}} = AsciiArt.new("donut", fps: 1000)
      assert AsciiArt.new("nope") == {:error, :unknown_piece}
    end
  end

  describe "ink" do
    alias AsciiArt.TestPieces.Bar

    test "colours a piece drawn in one ink, its text exactly as without" do
      {plain, _} = "big-text" |> AsciiArt.new!() |> AsciiArt.frame(1.0)

      {inked, _} =
        "big-text" |> AsciiArt.new!(ink: ["#ff5f6d", "#ffc371"]) |> AsciiArt.frame(1.0)

      assert inked.text == plain.text
      assert byte_size(inked.colors) == plain.cols * plain.rows
      assert hd(inked.palette) == "#ff5f6d" and List.last(inked.palette) == "#ffc371"
      assert Frame.color_at(inked, 0, 0) == "#ff5f6d"
      assert Frame.color_at(inked, plain.cols - 1, 0) == "#ffc371"
      assert inked.ground == nil
    end

    test "a coloured piece keeps its own palette, unless drawn in one ink" do
      {own, _} = "elixir" |> AsciiArt.new!(ink: "#ff8800") |> AsciiArt.frame(0.0)
      assert own.palette == AsciiArt.meta!("elixir").palette

      {inked, _} =
        "night-coast" |> AsciiArt.new!(ink: "#ff8800", color: false) |> AsciiArt.frame(0.0)

      assert inked.palette == ["#ff8800"] and inked.ground == nil
    end

    test "follows a piece's size as its options change it" do
      anim = AsciiArt.new!(Bar, options: %{width: 3}, ink: "#000,#fff")
      {frame, anim} = AsciiArt.frame(anim, 0.0)
      assert byte_size(frame.colors) == 3

      {frame, _} = anim |> AsciiArt.put_options!(width: 5) |> AsciiArt.frame(0.0)
      assert byte_size(frame.colors) == 5
      assert Frame.color_at(frame, 2, 0) == "#808080"
      assert Frame.color_at(frame, 4, 0) == "#ffffff"
    end

    test "is checked" do
      assert AsciiArt.new("donut", ink: "red") == {:error, {:invalid_option, :ink}}

      assert AsciiArt.new("donut", ink: "#fff", gradient: "up") ==
               {:error, {:invalid_option, :gradient}}
    end
  end

  describe "put_options/2" do
    alias AsciiArt.TestPieces.{Bar, Blink}

    test "merges new options over the animation's own, checked as new/2 checks them" do
      anim = AsciiArt.new!(Bar, options: %{value: 20})
      assert {:ok, anim} = AsciiArt.put_options(anim, %{"width" => "20"})
      assert anim.options.value == 20 and anim.options.width == 20

      {frame, _} = AsciiArt.frame(anim, 0.0)
      assert frame.text == "####................"

      assert AsciiArt.put_options(anim, %{"evil" => 1}) == {:error, {:invalid_option, "evil"}}
      assert {:ok, %{options: %{width: 80}}} = AsciiArt.put_options(anim, width: 500)
    end

    test "a piece whose size follows its options is that size" do
      {frame, _} = Bar |> AsciiArt.new!(options: %{width: 3, value: 100}) |> AsciiArt.frame(0.0)
      assert {frame.cols, frame.rows, frame.text} == {3, 1, "###"}
    end

    test "a piece with update/2 carries its state over; one without starts afresh" do
      anim =
        AsciiArt.new!(Bar) |> AsciiArt.put_options!(value: 50) |> AsciiArt.put_options!(value: 60)

      assert anim.state.updates == 2

      {frame, _} =
        Blink |> AsciiArt.new!() |> AsciiArt.put_options!(dot: "o") |> AsciiArt.frame(0.0)

      assert frame.text == " o "
    end

    test "shapes say what an option takes where its default cannot" do
      assert {:ok, %{options: %{marks: [1, 2.5]}}} =
               AsciiArt.new(Bar, options: %{marks: [1, 2.5]})

      assert {:ok, %{options: %{marks: [3, 4]}}} =
               AsciiArt.new(Bar, options: %{"marks" => "[3, 4]"})

      assert AsciiArt.new(Bar, options: %{marks: ["x"]}) == {:error, {:invalid_option, :marks}}
    end
  end

  describe "still/2" do
    alias AsciiArt.TestPieces.Noted

    defp inits do
      Stream.repeatedly(fn -> receive(do: (:init -> 1), after: (0 -> nil)) end)
      |> Enum.take_while(& &1)
      |> length()
    end

    test "frame 0, drawn once with the default options, then kept" do
      Process.put(:init_watch, true)
      assert {:ok, %AsciiArt.Frame{text: "#0", t: +0.0}} = AsciiArt.still(Noted)
      assert {:ok, %AsciiArt.Frame{text: "#0"}} = AsciiArt.still(Noted)
      assert inits() <= 1

      # Other options are drawn each time, never kept.
      assert {:ok, %AsciiArt.Frame{text: "x0"}} = AsciiArt.still(Noted, options: %{mark: "x"})
      assert {:ok, %AsciiArt.Frame{text: "x0"}} = AsciiArt.still(Noted, options: %{mark: "x"})
      assert inits() == 2
    end

    test "kept apart for paper and one ink, and as a piece's own still" do
      {:ok, ink} = AsciiArt.still("elixir")
      {:ok, mono} = AsciiArt.still("elixir", color: false)
      assert ink.colors != nil and mono.colors == nil
      assert ink.text == AsciiArt.render!("elixir")
    end

    test "in ink, the kept still coloured: inks are not kept apart" do
      Process.put(:init_watch, true)
      {:ok, plain} = AsciiArt.still(Noted)
      {:ok, inked} = AsciiArt.still(Noted, ink: "#ff8800")
      {:ok, other} = AsciiArt.still(Noted, ink: "#00ff88")
      assert inits() <= 1
      assert inked.text == plain.text and plain.colors == nil
      assert {inked.palette, other.palette} == {["#ff8800"], ["#00ff88"]}
      assert AsciiArt.still(Noted) == {:ok, plain}
    end

    test "a piece that reads the clock is never kept" do
      now = ~U[2026-03-14 15:09:26Z]
      {:ok, a} = AsciiArt.still("digital-clock", now: now)
      {:ok, b} = AsciiArt.still("digital-clock", now: DateTime.add(now, 3600))
      refute a.text == b.text
    end

    test "errors as new/2's" do
      assert AsciiArt.still("nope") == {:error, :unknown_piece}
      assert AsciiArt.still("elixir", options: %{evil: 1}) == {:error, {:invalid_option, :evil}}
    end
  end

  describe "render/3" do
    test "one frame from a fresh start" do
      assert {:ok, text} = AsciiArt.render("donut", 1.5)
      {:ok, anim} = AsciiArt.new("donut")
      assert {%Frame{text: ^text}, _} = AsciiArt.frame(anim, 1.5)
      assert AsciiArt.render!("donut") == elem(AsciiArt.render("donut"), 1)
      assert AsciiArt.render("nope") == {:error, :unknown_piece}
    end
  end

  describe "stream/2" do
    test "frames every 1/fps seconds" do
      frames = AsciiArt.stream!("donut", fps: 10) |> Enum.take(3)
      assert Enum.map(frames, & &1.t) == [0.0, 0.1, 0.2]
    end

    test "a still is one frame" do
      still = Enum.find(AsciiArt.pieces(), &(AsciiArt.meta!(&1).fps == 0))

      if still do
        assert AsciiArt.stream!(still) |> Enum.to_list() |> length() == 1
      end
    end
  end
end
