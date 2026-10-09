defmodule Ascii.DiagramExpansionTest do
  use ExUnit.Case, async: true

  alias Ascii.{Diagram, Frame, Mermaid}
  alias Ascii.Diagram.{Layout, Viewport}
  alias Ascii.Render.SVG

  test "short chains fit ordinary terminal widths with local connector spacing" do
    for {count, width} <- [{5, 80}, {8, 120}], direction <- [:lr, :rl] do
      nodes = for i <- 1..count, do: %{id: "n#{i}", label: "N#{i}"}
      edges = for i <- 1..(count - 1), do: %{from: "n#{i}", to: "n#{i + 1}"}
      assert {:ok, diagram} = Diagram.flowchart(nodes, edges, direction: direction)
      assert {:ok, layout} = Diagram.layout(diagram, max_cols: width)
      assert layout.cols <= width
      assert_clear(layout)
      assert {:ok, frame} = Layout.frame(layout)
      assert_frame(frame)
    end
  end

  test "nested flowchart groups retain containment, routing, colours and identity" do
    source = """
    flowchart LR
    U[User] --> A
    subgraph app [Application]
      subgraph svc [Service]
        A[API] --> B[Worker]
      end
      D[Database]
      B -->|store| D
    end
    style svc stroke:#0f0,color:#f00
    """

    assert {:ok, diagram} = Mermaid.parse(source)
    assert {:ok, layout} = Diagram.layout(diagram)
    assert_contains(layout.boundaries["app"], layout.boundaries["svc"])
    assert_contains(layout.boundaries["svc"], layout.nodes["A"])
    assert_contains(layout.boundaries["app"], layout.nodes["D"])
    assert_clear(layout)
    assert {:ok, frame} = Layout.frame(layout)
    group = layout.boundaries["svc"]
    assert Frame.color_at(frame, group.x, group.y) == "#00ff00"
    assert Layout.hit_at(layout, group.x, group.y) == {:boundary, "svc"}
    assert frame.text =~ "Application"
    assert frame.text =~ "Service"
    assert frame.text =~ "store"
    assert Diagram.layout(diagram) == {:ok, layout}
  end

  test "native groups validate parents, membership, IDs and endpoint references" do
    assert {:ok, diagram} = Diagram.flowchart([%{id: "a", group: "g"}], [], groups: [%{id: "g"}])
    assert {:ok, layout} = Diagram.layout(diagram)
    assert_contains(layout.boundaries["g"], layout.nodes["a"])

    for groups <- [[%{id: "g", parent: "missing"}], [%{id: "g", parent: "g"}], [%{id: "a"}]] do
      assert {:error, {:invalid_diagram, _}} = Diagram.flowchart([%{id: "a"}], [], groups: groups)
    end

    assert {:error, {:invalid_diagram, _}} = Diagram.flowchart([%{id: "a", group: "missing"}], [])
    assert {:error, {:syntax, 3, _, _}} = Mermaid.parse("flowchart LR\nsubgraph g [Group]\nA")
    assert {:error, {:syntax, 2, _, _}} = Mermaid.parse("flowchart LR\nend")
  end

  test "Mermaid groups adopt referenced nodes and reject shape declarations that collide with groups" do
    assert {:ok, diagram} = Mermaid.parse("flowchart LR\nA[Node]\nsubgraph g [Group]\nA-->B\nend")
    assert Enum.find(diagram.data.nodes, &(&1.id == "A")).group == "g"

    assert {:error, {:syntax, _, _, _}} =
             Mermaid.parse("flowchart LR\nA[Node]\nsubgraph A [Group]\nB\nend")
  end

  test "group endpoints and local directions are retained" do
    source = "flowchart TB\nsubgraph g [Group]\ndirection LR\nA-->B\nend\ng-->C"
    assert {:ok, diagram} = Mermaid.parse(source)
    assert {:ok, layout} = Diagram.layout(diagram)
    assert layout.nodes["A"].x < layout.nodes["B"].x
    assert List.last(layout.edges).from == "g"
    assert {:ok, frame} = Layout.frame(layout)
    assert_frame(frame)
  end

  test "state diagrams retain composite states, choices, start/end and transition styles" do
    source = """
    stateDiagram-v2
    direction LR
    [*] --> Idle
    state "Working" as Work {
      [*] --> Running
      state decide <<choice>>
      Running --> decide: done
      decide --> Running: retry
      decide --> [*]: accepted
    }
    Idle --> Work: start
    Work --> [*]: finish
    """

    assert {:ok, diagram} = Mermaid.parse(source)
    assert diagram.type == :state
    assert Enum.find(diagram.data.states, &(&1.id == "Work")).kind == :composite
    assert Enum.find(diagram.data.states, &(&1.id == "Running")).parent == "Work"
    assert Enum.count(diagram.data.states, &(&1.kind == :initial)) == 2
    assert Enum.count(diagram.data.states, &(&1.kind == :final)) == 2
    assert {:ok, diagram} = Diagram.put_style(diagram, {:node, "Running"}, color: "#0f0")
    assert {:ok, layout} = Diagram.layout(diagram)
    assert_contains(layout.boundaries["Work"], layout.nodes["Running"])
    assert_clear(layout)
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    assert frame.text =~ "Working"
    assert frame.text =~ "retry"
    assert frame.text =~ "start"
    assert frame.text =~ "*"
    assert_frame(frame)
  end

  test "native state validation rejects impossible pseudo states and composite ancestry" do
    assert {:ok, diagram} =
             Diagram.state([%{id: "ready"}, %{id: "done", kind: :final}], [
               %{from: "ready", to: "done"}
             ])

    assert {:ok, _layout} = Diagram.layout(diagram)

    for states <- [[%{id: "a", parent: "missing"}], [%{id: "a", kind: :composite, parent: "a"}]] do
      assert {:error, {:invalid_diagram, _}} = Diagram.state(states, [])
    end

    assert {:error, {:invalid_diagram, _}} =
             Diagram.state([%{id: "end", kind: :final}, %{id: "a"}], [%{from: "end", to: "a"}])

    assert {:error, {:syntax, 2, _, _}} = Mermaid.parse("stateDiagram-v2\nstate X <<fork>>")
  end

  test "ER diagrams draw attributes, key constraints and cardinality at both endpoints" do
    source = """
    erDiagram
    direction LR
    CUSTOMER ||--o{ ORDER : places
    CUSTOMER {
      integer id PK
      string email UK "Login address"
    }
    ORDER {
      integer id PK
      integer customer_id FK
    }
    """

    assert {:ok, diagram} = Mermaid.parse(source)
    assert diagram.type == :er
    assert hd(diagram.data.edges).from_cardinality == :one
    assert hd(diagram.data.edges).to_cardinality == :zero_or_more
    assert hd(hd(diagram.data.entities).attributes).keys == [:pk]
    assert {:ok, diagram} = Diagram.put_style(diagram, {:node, "CUSTOMER"}, color: "#0ff")
    assert {:ok, diagram} = Diagram.put_style(diagram, {:edge, "edge-1"}, line_color: "#f00")
    assert {:ok, layout} = Diagram.layout(diagram)
    assert_clear(layout)
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)

    for text <- [
          "CUSTOMER",
          "ORDER",
          "integer id PK",
          "email UK",
          "Login address",
          "places",
          "o",
          "{"
        ] do
      assert frame.text =~ text
    end

    assert_frame(frame)
    assert IO.iodata_to_binary(SVG.render(frame)) =~ "CUSTOMER"
  end

  test "native ER constructors validate attributes and cardinalities" do
    entities = [
      %{id: "a", attributes: [%{name: "id", type: "integer", keys: [:pk, :fk]}]},
      %{id: "b"}
    ]

    assert {:ok, diagram} =
             Diagram.er(entities, [
               %{
                 from: "a",
                 to: "b",
                 from_cardinality: :one_or_more,
                 to_cardinality: :zero_or_one,
                 identifying: false
               }
             ])

    assert hd(diagram.data.edges).style == :dashed
    assert {:ok, _frame} = Diagram.render(diagram)

    assert {:error, {:invalid_diagram, _}} =
             Diagram.er(entities, [%{from: "a", to: "b", to_cardinality: :bogus}])

    assert {:error, {:invalid_diagram, _}} =
             Diagram.er([%{id: "a", attributes: [%{name: "id", keys: [:bogus]}]}], [])

    assert {:error, {:syntax, 3, _, _}} = Mermaid.parse("erDiagram\nA {\ninteger id XX\n}")
  end

  test "connectors leave and approach their endpoints in the declared direction" do
    for direction <- [:lr, :rl, :tb, :bt] do
      assert {:ok, diagram} =
               Diagram.flowchart(
                 [%{id: "a"}, %{id: "b", label: "Tall\nbox"}],
                 [%{from: "a", to: "b"}, %{from: "b", to: "b"}],
                 direction: direction
               )

      assert {:ok, layout} = Diagram.layout(diagram)
      edge = hd(layout.edges)
      [first, second | _] = edge.points
      [last, before | _] = Enum.reverse(edge.points)

      case direction do
        :lr -> assert elem(first, 0) < elem(second, 0) and elem(before, 0) < elem(last, 0)
        :rl -> assert elem(first, 0) > elem(second, 0) and elem(before, 0) > elem(last, 0)
        :tb -> assert elem(first, 1) < elem(second, 1) and elem(before, 1) < elem(last, 1)
        :bt -> assert elem(first, 1) > elem(second, 1) and elem(before, 1) > elem(last, 1)
      end

      self_edge = List.last(layout.edges)
      [last, before | _] = Enum.reverse(self_edge.points)
      assert elem(last, 0) == elem(before, 0) and elem(last, 1) > elem(before, 1)
      assert_clear(layout)
    end
  end

  test "ER end markers survive bends, identify both endpoints and inherit line colours" do
    assert {:ok, diagram} =
             Diagram.er(
               [%{id: "a"}, %{id: "b", attributes: [%{name: "id"}, %{name: "other"}]}],
               [
                 %{
                   from: "a",
                   to: "b",
                   from_cardinality: :one,
                   to_cardinality: :zero_or_more,
                   color: "#f00"
                 }
               ],
               direction: :lr
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    edge = hd(layout.edges)
    {x, y} = hd(edge.points)
    assert String.slice(Enum.at(frame.lines, y), x, 2) == "||"
    {x, y} = List.last(edge.points)
    assert String.slice(Enum.at(frame.lines, y), x - 1, 2) == "o{"
    assert Frame.color_at(frame, x, y) == "#ff0000"
  end

  test "stable layer ordering removes avoidable crossed relationships" do
    assert {:ok, diagram} =
             Diagram.flowchart(
               Enum.map(~w(a b c d), &%{id: &1}),
               [%{from: "a", to: "d"}, %{from: "b", to: "c"}],
               direction: :lr
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert layout.nodes["a"].y == layout.nodes["d"].y
    assert layout.nodes["b"].y == layout.nodes["c"].y
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    refute frame.text =~ "x"
  end

  test "nested group directions inherit and empty groups remain visible" do
    source =
      "flowchart TB\nsubgraph outer [Outer]\ndirection LR\nsubgraph inner [Inner]\nA-->B\nend\nend\nsubgraph empty [Empty]\nend"

    assert {:ok, layout} = Mermaid.compile(source)
    assert layout.nodes["A"].x < layout.nodes["B"].x
    assert_contains(layout.boundaries["outer"], layout.boundaries["inner"])
    assert {:ok, frame} = Layout.frame(layout)
    assert frame.text =~ "Empty"
    assert {:ok, diagram} = Diagram.flowchart([], [], groups: [%{id: "empty", label: "Empty"}])
    assert {:ok, frame} = Diagram.render(diagram)
    assert frame.text =~ "Empty"
  end

  test "crowded feedback and self-edge labels are never overprinted or routed through boxes" do
    nodes = Enum.map(~w(a b c d), &%{id: &1, label: "Node #{&1}"})

    edges =
      for {from, to, label} <- [
            {"a", "b", "first"},
            {"a", "c", "second"},
            {"b", "d", "third"},
            {"c", "d", "fourth"},
            {"d", "a", "feedback"},
            {"b", "b", "self"}
          ],
          do: %{from: from, to: to, label: label}

    for direction <- [:lr, :rl, :tb, :bt] do
      assert {:ok, diagram} = Diagram.flowchart(nodes, edges, direction: direction)
      assert {:ok, layout} = Diagram.layout(diagram)
      assert_clear(layout)
      assert {:ok, frame} = Layout.frame(layout)

      for edge <- layout.edges, {line, row} <- Enum.with_index(edge.label_lines) do
        assert String.slice(
                 Enum.at(frame.lines, edge.label_y + row),
                 edge.label_x,
                 String.length(line)
               ) == line
      end
    end
  end

  test "every cardinality works on either end in every orientation" do
    for cardinality <- [:one, :zero_or_one, :one_or_more, :zero_or_more],
        direction <- [:lr, :rl, :tb, :bt] do
      assert {:ok, diagram} =
               Diagram.er(
                 [%{id: "a"}, %{id: "b"}],
                 [
                   %{
                     from: "a",
                     to: "b",
                     from_cardinality: cardinality,
                     to_cardinality: cardinality
                   }
                 ],
                 direction: direction
               )

      assert {:ok, layout} = Diagram.layout(diagram)
      assert_clear(layout)

      for charset <- [:ascii, :unicode] do
        assert {:ok, frame} = Layout.frame(layout, charset: charset)
        assert_frame(frame)
        edge = hd(layout.edges)

        for {x, y} <- [hd(edge.points), List.last(edge.points)] do
          refute String.at(Enum.at(frame.lines, y), x) in [" ", "x", "╳"]
          assert Layout.hit_at(layout, x, y) == {:edge, edge.id}
        end
      end
    end
  end

  test "ER relationships use distinct ports so cardinality markers cannot overwrite one another" do
    assert {:ok, diagram} =
             Diagram.er(
               [%{id: "a"}, %{id: "b"}, %{id: "c"}],
               [
                 %{from: "a", to: "b", from_cardinality: :one},
                 %{from: "a", to: "c", from_cardinality: :zero_or_more}
               ],
               direction: :lr
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert hd(hd(layout.edges).points) != hd(List.last(layout.edges).points)
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    [{x1, y1}, {x2, y2}] = Enum.map(layout.edges, &hd(&1.points))
    assert String.slice(Enum.at(frame.lines, y1), x1, 2) == "||"
    assert String.slice(Enum.at(frame.lines, y2), x2, 2) == "}o"
    assert_clear(layout)
  end

  test "shared flowchart branches join while unrelated intersections remain explicit" do
    assert {:ok, diagram} =
             Diagram.flowchart(
               Enum.map(~w(a b c), &%{id: &1}),
               [%{from: "a", to: "b"}, %{from: "a", to: "c"}],
               direction: :lr
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout, charset: :ascii)
    {x, y} = hd(hd(layout.edges).points)
    refute String.at(Enum.at(frame.lines, y), x) == "x"

    horizontal = %{
      id: "h",
      from: "a",
      to: "b",
      style: :solid,
      arrow: false,
      points: [{0, 2}, {4, 2}]
    }

    vertical = %{
      id: "v",
      from: "c",
      to: "d",
      style: :solid,
      arrow: false,
      points: [{2, 0}, {2, 4}]
    }

    crossing = %Layout{cols: 5, rows: 5, commands: [{:path, horizontal}, {:path, vertical}]}
    assert {:ok, frame} = Layout.frame(crossing, charset: :ascii)
    assert String.at(Enum.at(frame.lines, 2), 2) == "x"
    assert {:ok, frame} = Layout.frame(crossing, charset: :unicode)
    assert String.at(Enum.at(frame.lines, 2), 2) == "╳"
  end

  test "invalid and oversized models are rejected consistently across new families" do
    for constructor <- [&Diagram.state/2, &Diagram.er/2],
        records <- [[%{id: "a"}, %{id: "a"}], Enum.map(1..65, &%{id: "n#{&1}"})] do
      assert {:error, {:invalid_diagram, _}} = constructor.(records, [])
    end

    assert {:error, {:invalid_diagram, _}} =
             Diagram.er([%{id: "a", attributes: [%{name: "id"}, %{name: "id"}]}], [])

    assert {:error, {:invalid_diagram, _}} =
             Diagram.c4(:context, [%{id: "same"}], [], boundaries: [%{id: "same"}])

    assert {:error, {:syntax, 3, _, _}} = Mermaid.parse("stateDiagram-v2\nstate X {\nstate X {")
    assert {:error, {:syntax, 2, _, _}} = Mermaid.parse("erDiagram\n}")
  end

  test "viewports crop characters and colours together, pad edges and translate hits" do
    assert {:ok, layout} =
             Mermaid.compile("flowchart LR\nA[Alpha]-->B[Beta]\nstyle B stroke:#f00")

    assert {:ok, whole} = Layout.frame(layout)
    b = layout.nodes["B"]

    assert {:ok, viewport} =
             Layout.viewport(layout, x: b.x, y: b.y, cols: b.width + 2, rows: b.height + 1)

    assert {:ok, frame} = Viewport.frame(viewport)
    assert frame.cols == b.width + 2
    assert frame.rows == b.height + 1
    assert Frame.color_at(frame, 0, 0) == Frame.color_at(whole, b.x, b.y)
    assert Viewport.hit_at(viewport, 1, 1) == {:node, "B"}
    assert Viewport.hit_at(viewport, -1, 0) == nil
    assert Viewport.to_layout(viewport, 1, 1) == {b.x + 1, b.y + 1}
    assert Viewport.to_viewport(viewport, b.x + 1, b.y + 1) == {1, 1}
    assert {:ok, shifted} = Viewport.pan(viewport, 2, 1)
    assert shifted.x == b.x + 2 and shifted.y == b.y + 1

    assert {:ok, beyond} =
             Layout.viewport(layout, x: layout.cols, y: layout.rows, cols: 4, rows: 2)

    assert {:ok, blank} = Viewport.frame(beyond)
    assert blank.text == "    \n    "
    assert {:error, {:invalid_option, :x}} = Layout.viewport(layout, x: -1, cols: 4, rows: 2)
    assert {:error, {:too_large, _}} = Layout.viewport(layout, cols: 2000, rows: 1000)
    assert_frame(frame)
  end

  test "compiled selection styling reuses geometry and updates entity attributes" do
    assert {:ok, diagram} =
             Diagram.er(
               [%{id: "a", attributes: [%{name: "id", type: "integer"}]}, %{id: "b"}],
               [%{id: "owns", from: "a", to: "b", label: "owns"}],
               direction: :lr
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, before} = Layout.frame(layout)
    assert {:ok, selected} = Layout.put_style(layout, {:node, "a"}, border_color: "#f00")

    assert {:ok, selected} =
             Layout.put_style(selected, {:edge, "owns"}, line_color: "#0f0", label_color: "#00f")

    assert {:ok, selected} =
             Layout.put_style(selected, {:attribute, "a", "id"}, label_color: "#ff0")

    assert {:ok, after_frame} = Layout.frame(selected)
    assert after_frame.text == before.text
    assert Enum.map(selected.edges, & &1.points) == Enum.map(layout.edges, & &1.points)
    a = selected.nodes["a"]

    assert {a.x, a.y, a.width, a.height} ==
             {layout.nodes["a"].x, layout.nodes["a"].y, layout.nodes["a"].width,
              layout.nodes["a"].height}

    assert Frame.color_at(after_frame, a.x, a.y) == "#ff0000"
    assert Frame.color_at(after_frame, a.x + 2, a.y + hd(a.attributes).row) == "#ffff00"
    assert Layout.hit_at(selected, a.x + 2, a.y + hd(a.attributes).row) == {:attribute, "a", "id"}
    edge = hd(selected.edges)
    assert Frame.color_at(after_frame, edge.label_x, edge.label_y) == "#0000ff"

    assert {:error, {:invalid_diagram, _}} =
             Layout.put_style(layout, {:node, "missing"}, color: "#fff")

    assert {:error, {:invalid_diagram, _}} =
             Layout.put_style(layout, {:node, "a"}, color: "bogus")

    assert {:ok, recoloured} =
             Diagram.put_style(diagram, {:attribute, "a", "id"}, label_color: "#ff0")

    assert {:ok, frame} = Diagram.render(recoloured)
    assert Frame.color_at(frame, a.x + 2, a.y + hd(a.attributes).row) == "#ffff00"
  end

  test "every viewport cell matches full rendering even when coloured strokes are clipped" do
    source =
      "flowchart LR\nA[Café]-->B{Ready?}\nB-->A\nstyle A color:#0f0,stroke:#f00\nlinkStyle 0 stroke:#00f"

    assert {:ok, layout} = Mermaid.compile(source)

    for charset <- [:ascii, :unicode] do
      assert {:ok, full} = Layout.frame(layout, charset: charset)

      for {x, y} <- [{0, 0}, {4, 5}, {layout.cols - 3, layout.rows - 2}, {layout.cols + 1, 0}] do
        assert {:ok, viewport} = Layout.viewport(layout, x: x, y: y, cols: 9, rows: 7)
        assert {:ok, cropped} = Viewport.frame(viewport, charset: charset)

        for cx <- 0..8, cy <- 0..6 do
          expected =
            if x + cx < full.cols and y + cy < full.rows,
              do: String.at(Enum.at(full.lines, y + cy), x + cx),
              else: " "

          color =
            if x + cx < full.cols and y + cy < full.rows,
              do: Frame.color_at(full, x + cx, y + cy),
              else: nil

          assert String.at(Enum.at(cropped.lines, cy), cx) == expected
          assert Frame.color_at(cropped, cx, cy) == color
        end
      end
    end
  end

  defp assert_contains(outer, inner) do
    assert inner.x > outer.x and inner.y > outer.y
    assert inner.x + inner.width < outer.x + outer.width
    assert inner.y + inner.height < outer.y + outer.height
  end

  defp assert_clear(layout) do
    for edge <- layout.edges,
        [{ax, ay}, {bx, by}] <- Enum.chunk_every(edge.points, 2, 1, :discard),
        node <- Map.values(layout.nodes) do
      assert ax == bx or ay == by

      crosses? =
        if ax == bx,
          do:
            ax >= node.x and ax < node.x + node.width and max(ay, by) >= node.y and
              min(ay, by) < node.y + node.height,
          else:
            ay >= node.y and ay < node.y + node.height and max(ax, bx) >= node.x and
              min(ax, bx) < node.x + node.width

      refute crosses?, "#{edge.id} crosses #{node.id}"
    end
  end

  defp assert_frame(frame) do
    assert frame.text == Enum.join(frame.lines, "\n")
    assert length(frame.lines) == frame.rows
    assert Enum.all?(frame.lines, &(length(String.codepoints(&1)) == frame.cols))
    if frame.colors, do: assert(byte_size(frame.colors) == frame.cols * frame.rows)
  end
end
