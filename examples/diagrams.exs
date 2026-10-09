# Native diagrams, without a browser or Node. Each source can instead be
# constructed from application data with Ascii.Diagram's constructors.
examples = [
  {"Flowchart",
   """
   flowchart LR
   A[Request] -->|send| B(Worker)
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
