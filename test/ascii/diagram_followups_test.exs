defmodule Ascii.DiagramFollowupsTest do
  use ExUnit.Case, async: true

  alias Ascii.{Diagram, Frame, Mermaid}
  alias Ascii.Diagram.Layout

  test "palette changes force frame deltas to redraw recoloured elements" do
    assert {:ok, diagram} = Diagram.flowchart([%{id: "a", label: "Alpha", color: "#f00"}], [])
    assert {:ok, before} = Diagram.render(diagram)
    assert {:ok, diagram} = Diagram.put_style(diagram, {:node, "a"}, color: "#00f")
    assert {:ok, after_frame} = Diagram.render(diagram)
    assert before.text == after_frame.text
    assert before.colors == after_frame.colors
    assert before.palette != after_frame.palette
    assert Frame.changes(before, after_frame) != []
  end

  test "optional element colours override the theme without changing the picture" do
    nodes = [%{id: "a", label: "Alpha"}, %{id: "b", label: "Beta"}]
    edges = [%{id: "send", from: "a", to: "b", label: "send"}]
    assert {:ok, plain} = Diagram.flowchart(nodes, edges, direction: :lr)

    assert {:ok, colored} =
             Diagram.put_style(plain, {:node, "a"}, color: "#f00", label_color: "#0f0")

    assert {:ok, colored} = Diagram.put_style(colored, {:edge, "send"}, color: "#00f")
    assert {:ok, layout} = Diagram.layout(colored)
    assert {:ok, frame} = Layout.frame(layout, theme: %{node: "#888", label: "#aaa"})
    a = layout.nodes["a"]
    b = layout.nodes["b"]
    assert Frame.color_at(frame, a.x, a.y) == "#ff0000"
    assert Frame.color_at(frame, a.x + 2, a.y + 1) == "#00ff00"
    assert Frame.color_at(frame, b.x, b.y) == "#888888"
    {x, y} = hd(layout.edges).points |> List.last()
    assert Frame.color_at(frame, x, y) == "#0000ff"
    assert {:ok, before} = Diagram.render(plain)
    assert before.text == frame.text
    assert {:ok, mono} = Diagram.render(colored, color: false)
    assert mono.colors == nil
    assert mono.text == before.text

    assert {:error, {:invalid_diagram, _}} =
             Diagram.put_style(plain, {:node, "missing"}, color: "#f00")

    assert {:error, {:invalid_diagram, _}} =
             Diagram.put_style(plain, {:node, "a"}, color: "bogus")
  end

  test "constructor colours and CSS variables work without colouring other elements" do
    assert {:ok, diagram} =
             Diagram.flowchart(
               [
                 %{id: "a", color: "var(--accent, #f00)", border_color: "#0f0"},
                 %{id: "b"}
               ],
               []
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout)
    a = layout.nodes["a"]
    b = layout.nodes["b"]
    assert Frame.color_at(frame, a.x, a.y) == "#00ff00"
    assert Frame.color_at(frame, a.x + 2, a.y + 1) == "var(--accent, #ff0000)"
    assert Frame.color_at(frame, b.x, b.y) == nil
  end

  test "labels normalize NFC and retain single-cell Unicode in all frame positions" do
    assert {:ok, diagram} =
             Diagram.flowchart(
               [%{id: "a", label: "Cafe\u0301 Δοκιμή Привет €", color: "#f00"}],
               []
             )

    assert hd(diagram.data.nodes).label == "Café Δοκιμή Привет €"
    assert {:ok, layout} = Diagram.layout(diagram, label_width: 8)
    assert {:ok, frame} = Layout.frame(layout)
    assert_frame(frame)
    assert frame.text =~ "Café"
    assert {:ok, parsed} = Mermaid.parse("flowchart LR\nA[\"Δοκιμή\"] -->|café| B")
    assert hd(parsed.data.nodes).label == "Δοκιμή"

    for label <- ["界", "😀", "a\u200D", "\u0301", "bad\tlabel"] do
      assert {:error, {:invalid_diagram, _}} = Diagram.flowchart([%{id: "a", label: label}], [])
    end
  end

  test "nested C4 boundaries contain descendants and retain their colours and hit targets" do
    assert {:ok, diagram} =
             Diagram.c4(
               :component,
               [
                 %{id: "api", label: "API", boundary: "service"},
                 %{id: "db", label: "Database", boundary: "app"}
               ],
               [%{from: "api", to: "db", label: "reads", color: "#0ff"}],
               boundaries: [
                 %{id: "app", label: "Application", color: "#f00"},
                 %{id: "service", label: "Service", parent: "app", color: "#0f0"}
               ]
             )

    assert {:ok, layout} = Diagram.layout(diagram)
    assert_contains(layout.boundaries["app"], layout.boundaries["service"])
    assert_contains(layout.boundaries["service"], layout.nodes["api"])
    assert_contains(layout.boundaries["app"], layout.nodes["db"])
    assert {:ok, frame} = Layout.frame(layout)

    for {id, color} <- [{"app", "#ff0000"}, {"service", "#00ff00"}] do
      b = layout.boundaries[id]
      assert Frame.color_at(frame, b.x, b.y) == color
      assert Layout.hit_at(layout, b.x, b.y) == {:boundary, id}
    end

    assert_routes_clear(layout)
    assert_frame(frame)
  end

  test "boundary parent cycles and missing parents are rejected" do
    elements = [%{id: "x"}]

    for boundaries <- [
          [%{id: "a", parent: "missing"}],
          [%{id: "a", parent: "a"}],
          [%{id: "a", parent: "b"}, %{id: "b", parent: "a"}]
        ] do
      assert {:error, {:invalid_diagram, _}} =
               Diagram.c4(:context, elements, [], boundaries: boundaries)
    end
  end

  test "nested sequence fragments preserve branches, order and activations" do
    events = [
      %{
        kind: :loop,
        id: "retry",
        label: "retry",
        color: "#f00",
        events: [
          %{
            kind: :alt,
            id: "decision",
            label: "valid",
            events: [
              %{from: "u", to: "api", label: "request"},
              %{kind: :activate, id: "work", participant: "api", color: "#0f0"},
              %{from: "api", to: "u", label: "accepted"},
              %{kind: :deactivate, participant: "api"}
            ],
            branches: [%{label: "invalid", events: [%{from: "api", to: "u", label: "rejected"}]}]
          }
        ]
      }
    ]

    assert {:ok, diagram} = Diagram.sequence([%{id: "u"}, %{id: "api"}], events)
    assert {:ok, layout} = Diagram.layout(diagram)
    assert Map.keys(layout.fragments) |> Enum.sort() == ["decision", "retry"]
    assert_contains(layout.fragments["retry"], layout.fragments["decision"])
    assert Enum.map(layout.edges, & &1.label) == ["request", "accepted", "rejected"]
    activation = layout.activations["work"]
    assert activation.height > 1
    assert {:ok, frame} = Layout.frame(layout)
    assert_frame(frame)
    assert frame.text =~ "loop retry"
    assert frame.text =~ "else invalid"
    assert Frame.color_at(frame, activation.x, activation.y + 1) == "#00ff00"
    f = layout.fragments["retry"]
    assert Frame.color_at(frame, f.x, f.y) == "#ff0000"
    assert Layout.hit_at(layout, f.x, f.y) == {:fragment, "retry"}
  end

  test "notes, nested activations and parallel branches have valid retained geometry" do
    source = """
    sequenceDiagram
    participant A as API
    participant B as Worker
    A->>+B: work
    activate B
    Note right of B: busy
    B-->>-A: inner done
    B-->>-A: outer done
    par first
      A->>B: one
    and second
      B->>A: two
    end
    opt cache hit
      Note over A,B: cached
    end
    """

    assert {:ok, diagram} = Mermaid.parse(source)
    assert {:ok, layout} = Diagram.layout(diagram)
    assert map_size(layout.activations) == 2
    assert map_size(layout.notes) == 2
    assert map_size(layout.fragments) == 2
    over = Enum.find(Map.values(layout.notes), &(&1.position == :over))
    left = layout.nodes["A"]
    right = layout.nodes["B"]
    assert over.x <= left.x + div(left.width, 2)
    assert over.x + over.width > right.x + div(right.width, 2)
    assert {:ok, frame} = Layout.frame(layout)
    assert_frame(frame)
    assert frame.text =~ "and second"
    assert frame.text =~ "cached"
  end

  test "sequence structure errors are rejected at their source statements" do
    for {source, line} <- [
          {"sequenceDiagram\nparticipant A\ndeactivate A", 3},
          {"sequenceDiagram\nparticipant A\nelse other", 3},
          {"sequenceDiagram\nparticipant A\nloop retry", 3},
          {"sequenceDiagram\nparticipant A\nend", 3}
        ] do
      assert {:error, {:syntax, ^line, _, _}} = Mermaid.parse(source)
    end

    assert {:error, {:invalid_diagram, _}} =
             Diagram.sequence([%{id: "a"}], [%{kind: :deactivate, participant: "a"}])
  end

  test "styles select nested sequence notes, fragments, activations and messages by ID" do
    events = [
      %{
        kind: :loop,
        id: "retry",
        label: "retry",
        events: [
          %{id: "send", from: "a", to: "b", label: "request"},
          %{kind: :activate, id: "work", participant: "b"},
          %{kind: :note, id: "info", participants: ["b"], position: :right, label: "working"},
          %{kind: :deactivate, participant: "b"}
        ]
      }
    ]

    assert {:ok, diagram} = Diagram.sequence([%{id: "a"}, %{id: "b"}], events)
    assert {:ok, before} = Diagram.render(diagram)
    assert {:ok, diagram} = Diagram.put_style(diagram, {:fragment, "retry"}, color: "#f00")
    assert {:ok, diagram} = Diagram.put_style(diagram, {:note, "info"}, label_color: "#0f0")
    assert {:ok, diagram} = Diagram.put_style(diagram, {:activation, "work"}, color: "#00f")
    assert {:ok, diagram} = Diagram.put_style(diagram, {:edge, "send"}, line_color: "#ff0")
    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout)
    assert frame.text == before.text
    f = layout.fragments["retry"]
    n = layout.notes["info"]
    a = layout.activations["work"]
    assert Frame.color_at(frame, f.x, f.y) == "#ff0000"
    assert Frame.color_at(frame, n.x + 2, n.y + 1) == "#00ff00"
    assert Frame.color_at(frame, a.x, a.y + 1) == "#0000ff"
    assert Layout.hit_at(layout, n.x + 1, n.y + 1) == {:note, "info"}
    assert {:ok, cleared} = Diagram.put_style(diagram, {:fragment, "retry"}, color: nil)
    assert {:ok, frame} = Diagram.render(cleared, theme: %{fragment: "#aaa"})
    assert Frame.color_at(frame, f.x, f.y) == "#aaaaaa"
  end

  test "multiline Unicode boundary headers keep descendants and frame rows intact" do
    assert {:ok, diagram} =
             Diagram.c4(:context, [%{id: "x", label: "Café", boundary: "b"}], [],
               boundaries: [%{id: "b", label: "Δοκιμή\nApplication title", color: "#f00"}]
             )

    assert {:ok, layout} = Diagram.layout(diagram, label_width: 8)
    assert {:ok, frame} = Layout.frame(layout)
    assert_frame(frame)
    assert_contains(layout.boundaries["b"], layout.nodes["x"])
    assert frame.text =~ "Δοκιμή"
    assert frame.text =~ "Café"
  end

  test "fragment limits and activation balance apply before drawing" do
    leaf = %{from: "a", to: "a", label: "work"}
    nested = Enum.reduce(1..9, [leaf], fn _, events -> [%{kind: :loop, events: events}] end)
    assert {:error, {:invalid_diagram, _}} = Diagram.sequence([%{id: "a"}], nested)
    source = "sequenceDiagram\nparticipant A\nalt valid\nactivate A\nelse invalid\nend"
    assert {:error, {:syntax, 5, _, _}} = Mermaid.parse(source)

    source =
      "sequenceDiagram\nparticipant A\ncritical save\nA->>A: save\noption offline\nA->>A: queue\nend\nbreak finish\nA->>A: stop\nend"

    assert {:ok, layout} = Mermaid.compile(source)
    assert map_size(layout.fragments) == 2
    assert {:ok, frame} = Layout.frame(layout)
    assert_frame(frame)
    assert frame.text =~ "option offline"
    assert frame.text =~ "break finish"
  end

  test "Mermaid flowchart and C4 element style statements select their intended targets" do
    flow =
      "flowchart LR\nA-->B\nstyle A color:#0f0,stroke:#f00\nlinkStyle 0 stroke:#00f,color:#ff0"

    assert {:ok, diagram} = Mermaid.parse(flow)
    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout)
    a = layout.nodes["A"]
    assert Frame.color_at(frame, a.x, a.y) == "#ff0000"
    assert Frame.color_at(frame, a.x + 2, a.y + 1) == "#00ff00"
    assert {:error, {:syntax, 3, _, _}} = Mermaid.parse("flowchart LR\nA\nstyle A fill:#fff")

    c4 = """
    C4Container
    System_Boundary(app, "App") {
      Container_Boundary(service, "Service") {
        Container(api, "API", "Phoenix")
      }
    }
    Person(u, "User")
    Rel(u, api, "uses")
    UpdateElementStyle(api, $fontColor="#0f0", $borderColor="#f00")
    UpdateRelStyle(u, api, $lineColor="#00f")
    """

    assert {:ok, diagram} = Mermaid.parse(c4)
    assert Enum.find(diagram.data.boundaries, &(&1.id == "service")).parent == "app"
    assert {:ok, layout} = Diagram.layout(diagram)
    assert {:ok, frame} = Layout.frame(layout)
    api = layout.nodes["api"]
    assert Frame.color_at(frame, api.x, api.y) == "#ff0000"
    assert Frame.color_at(frame, api.x + 2, api.y + 1) == "#00ff00"
  end

  test "excess colours return an error rather than wrapping palette indices" do
    messages =
      for i <- 1..128 do
        %{from: "a", to: "b", label: "message", color: hex(i), label_color: hex(i + 128)}
      end

    assert {:ok, diagram} = Diagram.sequence([%{id: "a", color: "#ffffff"}, %{id: "b"}], messages)
    assert {:error, {:too_many_colors, count}} = Diagram.render(diagram, max_rows: 1000)
    assert count > 256
  end

  defp hex(i), do: "#" <> (i |> Integer.to_string(16) |> String.pad_leading(6, "0"))

  defp assert_contains(outer, inner) do
    assert inner.x > outer.x and inner.y > outer.y
    assert inner.x + inner.width < outer.x + outer.width
    assert inner.y + inner.height < outer.y + outer.height
  end

  defp assert_frame(frame) do
    assert frame.rows == length(frame.lines)
    assert frame.text == Enum.join(frame.lines, "\n")
    assert Enum.all?(frame.lines, &(length(String.codepoints(&1)) == frame.cols))
    if frame.colors, do: assert(byte_size(frame.colors) == frame.cols * frame.rows)
  end

  defp assert_routes_clear(layout) do
    for edge <- layout.edges,
        [{ax, ay}, {bx, by}] <- Enum.chunk_every(edge.points, 2, 1, :discard),
        n <- Map.values(layout.nodes) do
      crosses? =
        if ax == bx,
          do:
            ax >= n.x and ax < n.x + n.width and max(ay, by) >= n.y and
              min(ay, by) < n.y + n.height,
          else:
            ay >= n.y and ay < n.y + n.height and max(ax, bx) >= n.x and
              min(ax, bx) < n.x + n.width

      refute crosses?, "#{edge.id} crosses #{n.id}"
    end
  end
end
