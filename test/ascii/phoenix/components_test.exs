defmodule Ascii.Phoenix.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Ascii.Phoenix.Components

  test "a text piece is a pre holding frame 0, labelled for screen readers" do
    html = render_component(&Components.ascii/1, piece: "donut")

    assert html =~
             ~s(<pre role="img" aria-label="donut: a lit torus turning on two axes, after donut.c")

    assert html =~ Ascii.render!("donut") |> String.split("\n") |> Enum.at(10)
  end

  test "a label, a time and options" do
    html =
      render_component(&Components.ascii/1,
        piece: "typewriter",
        t: 1.0,
        options: %{"prefix" => "we make "},
        label: "typing"
      )

    assert html =~ ~s(aria-label="typing")
    assert html =~ "we make "
  end

  test "a coloured piece is spans of its palette over its ground" do
    html = render_component(&Components.ascii/1, piece: "night-coast")
    assert html =~ ~r/style="[^"]*background:#080b12"/
    assert html =~ ~s(<span style="color:#)
  end

  test "mono draws a coloured piece in one ink" do
    html = render_component(&Components.ascii/1, piece: "elixir", mono: true)
    refute html =~ "<span"
    assert html =~ "q88888888,"
  end

  test "ink colours a piece drawn in one ink, with no ground behind" do
    html = render_component(&Components.ascii/1, piece: "big-text", ink: ["#ff5f6d", "#ffc371"])
    assert html =~ ~s(<span style="color:#ff5f6d">)
    colours = ~r/color:#\w+/ |> Regex.scan(html) |> Enum.uniq()
    assert length(colours) > 2
    refute html =~ "background:"

    html = render_component(&Components.ascii/1, piece: "elixir", mono: true, ink: "#ff8800")
    assert html =~ ~s(<span style="color:#ff8800">)
  end

  test "colours for parts, the rest in the page's own" do
    html =
      render_component(&Components.ascii/1,
        piece: "boot-log",
        parts: %{"status.warn" => "#d29922"}
      )

    assert html =~ ~s(<span style="color:#d29922">[ WARN ])
    assert html =~ "started system logger"
    assert length(Regex.scan(~r/<span/, html)) == 1

    assert render_component(&Components.ascii/1, piece: "boot-log", parts: true) =~
             ~s(<span style="color:#3fb950">[  OK  ])
  end

  test "extra attributes pass through" do
    html = render_component(&Components.ascii/1, piece: "donut", class: "art", id: "d")
    assert html =~ ~s(class="art")
    assert html =~ ~s(id="d")
  end

  test "an unknown piece raises" do
    assert_raise ArgumentError, fn -> render_component(&Components.ascii/1, piece: "nope") end
  end

  describe "frame/1" do
    test "draws a frame you have as ascii/1 draws a piece's" do
      {frame, _} = "elixir" |> Ascii.new!() |> Ascii.frame(0.0)
      drawn = render_component(&Components.frame/1, frame: frame, label: "the logo")
      ascii = render_component(&Components.ascii/1, piece: "elixir", label: "the logo")

      text = &(&1 |> String.replace(~r/<[^>]+>/, "") |> String.replace("&#39;", "'"))
      assert text.(drawn) == text.(ascii)
      assert drawn =~ ~s(aria-label="the logo")

      # A scene's ground is behind it, as in ascii/1.
      {scene, _} = "night-coast" |> Ascii.new!() |> Ascii.frame(0.0)
      assert render_component(&Components.frame/1, frame: scene) =~ "background:#"
    end

    test "a text frame is its text, a row an element" do
      {frame, _} = "donut" |> Ascii.new!() |> Ascii.frame(1.0)
      drawn = render_component(&Components.frame/1, frame: frame)
      assert length(String.split(drawn, "<span")) - 1 == frame.rows

      assert drawn
             |> String.replace(~r/<[^>]+>/, "")
             |> String.contains?(Enum.at(frame.lines, 10))
    end
  end

  test "frame 0 of a piece is set up once, then kept" do
    Process.put(:init_watch, true)
    render_component(&Components.ascii/1, piece: Ascii.TestPieces.Noted)
    render_component(&Components.ascii/1, piece: Ascii.TestPieces.Noted)
    inits = Stream.repeatedly(fn -> receive(do: (:init -> 1), after: (0 -> nil)) end)
    assert inits |> Enum.take_while(& &1) |> length() <= 1
  end
end
