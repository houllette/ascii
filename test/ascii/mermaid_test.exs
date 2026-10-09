defmodule Ascii.MermaidTest do
  use ExUnit.Case, async: true

  alias Ascii.{Diagram, Mermaid}

  test "flowchart text compiles to the same model as programmatic input" do
    source = "flowchart LR\n%% comment\nA[Request] -->|send| B(Worker); B --> A"
    assert {:ok, parsed} = Mermaid.parse(source)

    assert {:ok, built} =
             Diagram.flowchart(
               [%{id: "A", label: "Request"}, %{id: "B", label: "Worker", shape: :rounded}],
               [%{from: "A", to: "B", label: "send"}, %{from: "B", to: "A"}],
               direction: :lr
             )

    assert parsed == built
    assert {:ok, frame} = Mermaid.render(source)
    assert frame.text =~ "Request"
    assert frame.text =~ "send"
  end

  test "flowchart declarations, quoted punctuation, chains and diamonds" do
    assert {:ok, diagram} =
             Mermaid.parse(~s(graph TD\nA["one; two --> three"] --> B{Valid?} --> C))

    assert Enum.map(diagram.data.nodes, & &1.label) == ["one; two --> three", "Valid?", "C"]
    assert Enum.map(diagram.data.nodes, & &1.shape) == [:rectangle, :diamond, :rectangle]
    assert {:ok, frame} = Diagram.render(diagram)
    assert frame.text =~ "Valid?"
  end

  test "sequence syntax preserves explicit order and creates implicit participants" do
    source =
      "sequenceDiagram\nactor U as User\nparticipant A as API\nU->>A: request\nA-->>U: response\nA->>DB: store"

    assert {:ok, diagram} = Mermaid.parse(source)
    assert diagram.type == :sequence
    assert Enum.map(diagram.data.participants, & &1.id) == ["U", "A", "DB"]
    assert Enum.at(diagram.data.messages, 1).style == :dashed
    assert {:ok, frame} = Mermaid.render(source)
    assert frame.text =~ "response"
  end

  test "C4 boundary syntax and quoted commas are retained" do
    source = """
    C4Container
    Person(user, "Customer")
    System_Boundary(app, "Application") {
    Container(api, "API", "Elixir, Phoenix", "Serves requests")
    ContainerDb(db, "Database", "PostgreSQL")
    }
    Rel(user, api, "Uses")
    Rel(api, db, "Reads", "SQL")
    """

    assert {:ok, diagram} = Mermaid.parse(source)
    assert diagram.type == :c4
    assert diagram.data.level == :container
    assert Enum.at(diagram.data.elements, 1).technology == "Elixir, Phoenix"
    assert Enum.at(diagram.data.elements, 1).boundary == "app"
    assert {:ok, frame} = Mermaid.render(source)
    assert frame.text =~ "Application"
    assert frame.text =~ "PostgreSQL"
  end

  test "errors carry source locations and unsupported statements never disappear" do
    assert {:error, {:syntax, 2, _, _}} = Mermaid.parse("flowchart LR\nA[unfinished")
    assert {:error, {:syntax, 2, _, _}} = Mermaid.parse("flowchart LR\nclick A callback")
    assert {:error, {:syntax, 2, _, _}} = Mermaid.parse("sequenceDiagram\nloop retry")
    assert {:error, {:syntax, 1, _, _}} = Mermaid.parse("pie\n\"a\": 10")

    assert {:error, {:syntax, 3, _, _}} =
             Mermaid.parse(~s|C4Context\nSystem_Boundary(app, "App") {\nPerson(u, "User")|)

    assert {:error, {:invalid_source, :size}} = Mermaid.parse(String.duplicate("a", 65_537))
    assert {:error, {:invalid_source, :encoding}} = Mermaid.parse(<<255>>)
    assert {:error, {:invalid_source, :type}} = Mermaid.parse(nil)
  end

  test "sources longer than the piece option limit retain every node" do
    source = "flowchart LR\n" <> Enum.map_join(1..20, "\n", &"n#{&1}[node number #{&1}]")
    assert byte_size(source) > 256
    assert {:ok, diagram} = Mermaid.parse(source)
    assert length(diagram.data.nodes) == 20
    assert List.last(diagram.data.nodes).id == "n20"
  end

  test "comments cannot swallow source through quotes, and compact arrows retain IDs" do
    assert {:ok, diagram} =
             Mermaid.parse("flowchart LR\n%% an unmatched \" quote\nnode-a-->node-b")

    assert Enum.map(diagram.data.nodes, & &1.id) == ["node-a", "node-b"]
    assert hd(diagram.data.edges).from == "node-a"
    assert hd(diagram.data.edges).to == "node-b"
  end

  test "native limits reject excess records without truncation" do
    source = "flowchart LR\n" <> Enum.map_join(1..65, "\n", &"n#{&1}")
    assert {:error, {:syntax, _, _, _}} = Mermaid.parse(source)
    source = "flowchart LR\n" <> String.duplicate("a\n", 256)
    assert {:error, {:invalid_source, :statements}} = Mermaid.parse(source)
  end
end
