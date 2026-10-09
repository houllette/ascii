# Native diagrams, without a browser or Node. Each source can instead be
# constructed from application data with Ascii.Diagram's constructors.
examples = [
  {"Flowchart",
   """
   flowchart LR
   A[Request] -->|send| B(Worker)
   subgraph app [Application]
     B --> C[Database]
   end
   style app stroke:#8b949e
   style B stroke:#58a6ff,color:#3fb950
   linkStyle 0 stroke:#d29922
   """},
  {"Sequence",
   """
   sequenceDiagram
   actor U as User
   participant A as API
   loop retry
     U->>+A: request
     alt valid
       A->>A: validate
       A-->>U: accepted
     else invalid
       A-->>U: rejected
     end
     deactivate A
   end
   Note over U,A: ready
   """},
  {"C4 containers",
   """
   C4Container
   Person(u, "Customer")
   System_Boundary(app, "Application") {
   Container_Boundary(service, "Service") {
     Container(api, "API", "Phoenix", "Serves requests")
   }
   ContainerDb(db, "Database", "PostgreSQL")
   }
   Rel(u, api, "Uses")
   Rel(api, db, "Reads", "SQL")
   UpdateElementStyle(api, $fontColor="#3fb950", $borderColor="#58a6ff")
   UpdateRelStyle(api, db, $lineColor="#d29922")
   """},
  {"State lifecycle",
   """
   stateDiagram-v2
   direction LR
   [*] --> Idle
   state "Working" as Work {
     [*] --> Running
     state Result <<choice>>
     Running --> Result: done
     Result --> Running: retry
     Result --> [*]: accepted
   }
   Idle --> Work: start
   Work --> [*]: finish
   """},
  {"Entity relationships",
   """
   erDiagram
   direction LR
   CUSTOMER ||--o{ ORDER : places
   CUSTOMER {
     integer id PK
     string email UK
   }
   ORDER {
     integer id PK
     integer customer_id FK
   }
   style CUSTOMER stroke:#58a6ff,color:#3fb950
   """}
]

for {title, source} <- examples do
  {:ok, diagram} = Ascii.Mermaid.parse(source)

  {:ok, diagram} =
    if diagram.type == :sequence,
      do: Ascii.Diagram.put_style(diagram, {:node, "A"}, color: "#58a6ff"),
      else: {:ok, diagram}

  {:ok, layout} = Ascii.Diagram.layout(diagram)
  {:ok, frame} = Ascii.Diagram.Layout.frame(layout)
  IO.puts("\n#{title} (#{frame.cols}x#{frame.rows})")
  output = if "--color" in System.argv(), do: Ascii.Render.ANSI.render(frame), else: frame.text
  IO.puts(output)
end

alias Ascii.Diagram.{Layout, Viewport}

# The consumer retains this layout and updates the window in its event handler.
source = "flowchart LR\n" <> Enum.map_join(1..11, ";", &"n#{&1}-->n#{&1 + 1}")
{:ok, layout} = Ascii.Mermaid.compile(source)
{:ok, selected} = Layout.put_style(layout, {:node, "n6"}, border_color: "#58a6ff")
{:ok, viewport} = Layout.viewport(selected, cols: 80, rows: 10)
{:ok, viewport} = Viewport.pan(viewport, 40, 0)
{:ok, frame} = Viewport.frame(viewport)
IO.puts("\nPanned viewport (80x10, origin #{viewport.x},#{viewport.y})")
output = if "--color" in System.argv(), do: Ascii.Render.ANSI.render(frame), else: frame.text
IO.puts(output)

node = selected.nodes["n6"]
{x, y} = Viewport.to_viewport(viewport, node.x + 1, node.y + 1)
IO.puts("Hit at #{x},#{y}: #{inspect(Viewport.hit_at(viewport, x, y))}")
