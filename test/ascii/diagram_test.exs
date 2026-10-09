defmodule Ascii.DiagramTest do
  use ExUnit.Case, async: true

  alias Ascii.{Diagram, Frame}
  alias Ascii.Diagram.Layout
  alias Ascii.Render.{HTML, SVG}

  test "flowcharts retain identity, route arrows and render through existing adapters" do
    assert {:ok, diagram} =
             Diagram.flowchart(
               [%{id: "a", label: "Request"}, %{id: "b", label: "Worker"}],
               [%{from: "a", to: "b", label: "send"}],
               direction: :lr
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    assert_frame(frame)
    assert frame.text =~ "Request"
    assert frame.text =~ "Worker"
    assert frame.text =~ "send"
    assert frame.text =~ ">"
    assert IO.iodata_to_binary(HTML.render(frame)) =~ "&gt;"
    assert IO.iodata_to_binary(SVG.render(frame)) =~ "<svg"

    %{x: x, y: y} = Map.fetch!(layout.nodes, "a")
    assert Layout.hit_at(layout, x + 1, y + 1) == {:node, "a"}
    assert Layout.hit_at(layout, -1, 0) == nil
    assert Diagram.layout(diagram) == {:ok, layout}
  end

  test "branches, merges, cycles, self edges and disconnected nodes have valid frames" do
    nodes = for id <- ~w(a b c d e), do: %{id: id, label: id}

    edges =
      for {from, to} <- [{"a", "b"}, {"a", "c"}, {"b", "d"}, {"c", "d"}, {"d", "a"}, {"c", "c"}],
          do: %{from: from, to: to}

    for direction <- [:lr, :rl, :tb, :bt] do
      assert {:ok, diagram} = Diagram.flowchart(nodes, edges, direction: direction)
      assert {:ok, layout} = Diagram.layout(diagram)
      assert map_size(layout.nodes) == 5
      assert length(layout.edges) == 6
      assert_routes_clear(layout)
      assert {:ok, frame} = Layout.frame(layout)
      assert_frame(frame)
    end
  end

  test "sequence message order, aliases, dashed returns and self calls are preserved" do
    assert {:ok, diagram} =
             Diagram.sequence(
               [%{id: "u", label: "User", kind: :actor}, %{id: "api", label: "API"}],
               [
                 %{from: "u", to: "api", label: "request"},
                 %{from: "api", to: "api", label: "validate"},
                 %{from: "api", to: "u", label: "response", style: :dashed}
               ]
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert Enum.map(layout.edges, & &1.id) == ["message-1", "message-2", "message-3"]
    assert Enum.map(layout.edges, & &1.y) == Enum.sort(Enum.map(layout.edges, & &1.y))
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    assert_frame(frame)
    assert frame.text =~ "request"
    assert frame.text =~ "validate"
    assert frame.text =~ "response"
    assert frame.text =~ "<"
    assert frame.text =~ "."
  end

  test "C4 levels retain types, technology, descriptions and boundaries" do
    for level <- [:context, :container, :component] do
      assert {:ok, diagram} =
               Diagram.c4(
                 level,
                 [
                   %{id: "u", label: "Customer", kind: :person},
                   %{
                     id: "api",
                     label: "API",
                     kind: :container,
                     technology: "Phoenix",
                     boundary: "app"
                   },
                   %{id: "db", label: "Database", kind: :database, boundary: "app"}
                 ],
                 [
                   %{from: "u", to: "api", label: "uses"},
                   %{from: "api", to: "db", label: "reads"}
                 ],
                 boundaries: [%{id: "app", label: "Application"}]
               )

      assert {:ok, layout} = Diagram.layout(diagram)
      assert {:ok, frame} = Layout.frame(layout)
      assert_frame(frame)
      assert frame.text =~ "Application"
      assert frame.text =~ "Phoenix"
      assert frame.text =~ "Person"
      assert map_size(layout.nodes) == 3
      assert_routes_clear(layout)
      %{x: x, y: y, width: w, height: h} = layout.boundaries["app"]

      for id <- ~w(api db) do
        node = layout.nodes[id]
        assert node.x > x and node.y > y
        assert node.x + node.width < x + w
        assert node.y + node.height < y + h
      end
    end
  end

  test "invalid IDs, references, labels and render options are errors, never truncated" do
    assert {:error, {:invalid_diagram, _}} = Diagram.flowchart([%{id: "a"}, %{id: "a"}], [])

    assert {:error, {:invalid_diagram, _}} =
             Diagram.flowchart([%{id: "a"}], [%{from: "a", to: "missing"}])

    assert {:error, {:invalid_diagram, _}} =
             Diagram.flowchart([%{id: "a", label: "bad\e[2J"}], [])

    assert {:error, {:invalid_diagram, _}} = Diagram.flowchart([%{id: "a", label: "😀"}], [])
    assert {:ok, diagram} = Diagram.flowchart([%{id: "a", label: String.duplicate("a", 300)}], [])
    assert {:ok, frame} = Diagram.render(diagram)
    assert frame.text |> String.codepoints() |> Enum.count(&(&1 == "a")) == 300
    assert {:error, {:invalid_option, :charset}} = Diagram.render(diagram, charset: :unknown)
    assert {:error, {:too_large, _}} = Diagram.render(diagram, max_cols: 2)

    assert {:error, {:invalid_option, :theme}} =
             Diagram.render(diagram, theme: %{node: "invalid"})
  end

  test "themes change colours without changing geometry or characters" do
    assert {:ok, diagram} = Diagram.flowchart([%{id: "a", label: "Hello"}], [])
    assert {:ok, plain} = Diagram.render(diagram)

    assert {:ok, tinted} =
             Diagram.render(diagram, theme: %{node: "#ff0000", label: "var(--ink, #fff)"})

    assert tinted.text == plain.text
    assert tinted.colors != nil
    assert Frame.color_at(tinted, 0, 0) == "#ff0000"
    assert {:ok, mono} = Diagram.render(diagram, theme: %{node: "#f00"}, color: false)
    assert mono.colors == nil
    assert mono.text == plain.text
  end

  test "mixed label and shape sizes leave every route outside all nodes" do
    nodes = [
      %{id: "a", label: "start"},
      %{id: "b", label: String.duplicate("wide", 8)},
      %{id: "c", label: "decision", shape: :diamond},
      %{id: "d", label: "finish"}
    ]

    edges =
      for {from, to} <- [{"a", "b"}, {"a", "c"}, {"b", "d"}, {"c", "d"}, {"d", "a"}],
          do: %{from: from, to: to, label: "one\ntwo\nthree"}

    for direction <- [:lr, :rl, :tb, :bt] do
      assert {:ok, diagram} = Diagram.flowchart(nodes, edges, direction: direction)
      assert {:ok, layout} = Diagram.layout(diagram, max_cols: 1000, max_rows: 500)
      assert_routes_clear(layout)
      assert {:ok, frame} = Layout.frame(layout, max_cols: 1000, max_rows: 500)
      assert_frame(frame)
    end
  end

  test "a lone node has a stable exact ASCII snapshot" do
    assert {:ok, diagram} = Diagram.flowchart([%{id: "a", label: "Hello"}], [])
    assert {:ok, frame} = Diagram.render(diagram, charset: :ascii)
    assert frame.text == "+-------+\n| Hello |\n+-------+"
  end

  defp assert_routes_clear(layout) do
    for edge <- layout.edges,
        [{ax, ay}, {bx, by}] <- Enum.chunk_every(edge.points, 2, 1, :discard) do
      assert ax == bx or ay == by

      for {x, y} <- [{ax, ay}, {bx, by}] do
        assert x >= 0 and x < layout.cols and y >= 0 and y < layout.rows
      end

      for node <- Map.values(layout.nodes) do
        crosses? =
          if ax == bx do
            ax >= node.x and ax < node.x + node.width and
              max(ay, by) >= node.y and min(ay, by) < node.y + node.height
          else
            ay >= node.y and ay < node.y + node.height and
              max(ax, bx) >= node.x and min(ax, bx) < node.x + node.width
          end

        refute crosses?, "#{edge.id} crosses node #{node.id}"
      end
    end
  end

  defp assert_frame(frame) do
    assert frame.rows == length(frame.lines)
    assert frame.text == Enum.join(frame.lines, "\n")
    assert Enum.all?(frame.lines, &(length(String.codepoints(&1)) == frame.cols))
    if frame.colors, do: assert(byte_size(frame.colors) == frame.cols * frame.rows)
  end
end
