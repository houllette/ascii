# Native diagrams

`Ascii.Diagram` draws flowcharts, sequences, C4 views, state diagrams and
entity relationship diagrams from application data. `Ascii.Mermaid` accepts a documented subset of Mermaid source and
builds the same models. Both produce ordinary `Ascii.Frame`s for text,
ANSI, HTML, SVG, Phoenix, ExRatatui and other existing consumers.

These native diagrams have their own deterministic layout and contracts.
The existing 191 upstream pieces retain their exact upstream fixtures.
Diagrams require no Node, browser, NIF or additional dependency.

## From application data

IDs are strings. Labels and relationship data can come from your application;
there is no need to generate a source language first.

```elixir
alias Ascii.Diagram

nodes = [
  %{id: "request", label: "Request"},
  %{id: "worker", label: "Worker", shape: :rounded}
]
edges = [%{from: "request", to: "worker", label: "send"}]

{:ok, diagram} = Diagram.flowchart(nodes, edges, direction: :lr)
{:ok, frame} = Diagram.render(diagram, charset: :ascii)
IO.puts(frame.text)
```

Nodes accept `:rectangle`, `:rounded` and `:diamond` shapes. Directions are
`:tb` (default), `:bt`, `:lr`, `:rl`. Branches, merges, disconnected nodes,
cycles and self edges are retained. Placement uses layers and stable barycentre ordering to reduce avoidable
crossings. Spacing depends on local labels rather than the total edge count.
Orthogonal routes avoid node boxes, group headers and existing relationship
labels. Distance, bends and crossings have deterministic routing costs;
congested labels receive an outer channel. These heuristics do not promise
an optimal layout. Default horizontal chains with short labels take 71 columns
for five nodes and 116 columns for eight nodes.

Every relationship takes `from`, `to`, optional `id`, `label` (default empty),
`style: :solid | :dashed` and `arrow: true | false`. Omitted relationship IDs
are assigned in order (`edge-1`, `edge-2`, ...).

## Nested flowchart groups

A node can name a group with `group: "app"`. Pass `groups:` definitions with
`id`, optional `label`, optional `parent` and optional local `direction`:

```elixir
{:ok, diagram} = Ascii.Diagram.flowchart(
  [%{id: "api", label: "API", group: "service"},
   %{id: "db", label: "Database", group: "app"}],
  [%{from: "api", to: "db", label: "reads"}],
  direction: :lr,
  groups: [%{id: "app", label: "Application", color: "#58a6ff"},
           %{id: "service", label: "Service", parent: "app"}]
)
```

Groups keep descendants together. Empty groups retain their labelled borders;
a diagram containing only groups is valid. Nodes and groups share one ID
namespace, and relationships may end at either. Missing memberships, missing
parents, parent cycles and duplicate IDs are errors. Local directions are
inherited by nested groups and govern relationships within that group;
relationships between groups use their common ancestor's direction. Unlike
Mermaid's browser layout, an outside connection does not cancel a local
direction.

Mermaid accepts `subgraph ID [Title]` (or `subgraph ID`), nested declarations,
`end`, local `direction` statements, and `style ID` for group foreground colours.
Subgraph nesting in source is limited to eight levels. A group reference used
as an edge endpoint is resolved to the group rather than an implicit node.

## Sequences

Sequences are ordered participants and messages, with their own layout.

```elixir
{:ok, diagram} = Ascii.Diagram.sequence(
  [%{id: "user", label: "User", kind: :actor}, %{id: "api", label: "API"}],
  [
    %{from: "user", to: "api", label: "request"},
    %{from: "api", to: "api", label: "validate"},
    %{from: "api", to: "user", label: "response", style: :dashed}
  ]
)
{:ok, frame} = Ascii.Diagram.render(diagram)
IO.puts(frame.text)
```

Participants take `id`, optional `label` and `kind: :participant | :actor`.
Both kinds currently use labelled boxes; actor identity remains in the model.
Messages use the relationship fields above, retain chronological order and
get IDs `message-1`, `message-2`, ... unless supplied. Self calls have a return
leg. Lifelines and message paths are drawn independently of the participant
boxes.

The ordered list also accepts notes, activations and nested fragments:

```elixir
events = [
  %{kind: :loop, id: "retry", label: "retry", events: [
    %{kind: :alt, id: "result", label: "valid", events: [
      %{from: "user", to: "api", label: "request"},
      %{kind: :activate, id: "work", participant: "api", color: "#58a6ff"},
      %{from: "api", to: "user", label: "accepted"},
      %{kind: :deactivate, participant: "api"}
    ], branches: [
      %{label: "invalid", events: [%{from: "api", to: "user", label: "rejected"}]}
    ]}
  ]},
  %{kind: :note, participants: ["api"], position: :right, label: "ready"}
]
{:ok, diagram} = Ascii.Diagram.sequence([%{id: "user"}, %{id: "api"}], events)
```

Fragment kinds are `:loop`, `:alt`, `:opt`, `:par`, `:critical`, `:break`.
Each takes `label`, `events`, optional `id` and optional foreground styles.
`:alt`, `:par` and `:critical` additionally take `branches`, an ordered list
of `%{label:, events:}` sections. Branches display as `else`, `and` or
`option` separators. Nesting is limited to eight levels.

Activation events take `participant:` and `kind: :activate | :deactivate`.
Nested activations stack. A deactivation requires a matching activation;
every fragment branch must leave the activation stack as it found it.
An activation left open at the end of the overall sequence extends to the
bottom. Notes take one participant for `position: :left | :right`, or one
or two for `:over` (default), plus `label:`.

Explicit event IDs stay stable through updates. Generated IDs use the
event's preorder position: `message-N` for messages, `event-N` for other
events. IDs must be unique across the whole event tree.

## C4 views

C4 models retain the view level, element types, technology, descriptions,
external status and boundaries. The view level is `:context`, `:container`
or `:component`; choose the elements appropriate to that level.

```elixir
{:ok, diagram} = Ascii.Diagram.c4(
  :container,
  [
    %{id: "customer", label: "Customer", kind: :person},
    %{id: "api", label: "API", kind: :container,
      technology: "Phoenix", description: "Serves requests", boundary: "app"},
    %{id: "db", label: "Database", kind: :database,
      technology: "PostgreSQL", boundary: "app"}
  ],
  [%{from: "customer", to: "api", label: "uses"},
   %{from: "api", to: "db", label: "reads"}],
  boundaries: [%{id: "app", label: "Application"}]
)
{:ok, frame} = Ascii.Diagram.render(diagram)
IO.puts(frame.text)
```

Kinds are `:person`, `:system`, `:container`, `:component`, `:database`,
`:queue`. Elements render as labelled boxes with a stereotype and optional
technology and description. `external: true` marks the stereotype as external.
Boundaries keep their members together, in declaration order. A boundary
can name another boundary with `parent: "app"`. Descendant boxes remain
inside their parents, including empty boundaries. Missing parents and parent
cycles are errors. Deployment and dynamic views are not yet supported.

```elixir
boundaries = [
  %{id: "app", label: "Application", color: "#58a6ff"},
  %{id: "service", label: "Service", parent: "app", color: "#3fb950"}
]
```

## State diagrams

State diagrams retain state identity and hierarchy independently of their
appearance. They describe transitions; the library does not execute them.

```elixir
{:ok, diagram} = Ascii.Diagram.state(
  [%{id: "start", kind: :initial},
   %{id: "idle", label: "Idle"},
   %{id: "work", label: "Working", kind: :composite},
   %{id: "running", parent: "work", color: "#3fb950"},
   %{id: "decision", parent: "work", kind: :choice},
   %{id: "done", kind: :final}],
  [%{from: "start", to: "idle"},
   %{from: "idle", to: "work", label: "start"},
   %{from: "running", to: "decision", label: "result"},
   %{from: "decision", to: "running", label: "retry"},
   %{from: "work", to: "done", label: "finish"}],
  direction: :lr
)
```

Kinds are `:state` (default), `:initial`, `:final`, `:choice`, `:composite`.
`parent:` must name a composite state. Initial states cannot have incoming
transitions, and final states cannot have outgoing transitions. Transitions
between ordinary states in different scopes are errors; use composite states
as endpoints for transitions between scopes. Self-transitions are supported.
Ordinary states use rounded boxes, choices use diamonds, and initial/final
states use distinct markers. Composite states appear in `layout.boundaries`
and accept `{:node, id}` styles on the model and `{:boundary, id}` styles on
both the model and compiled layout.

Mermaid headers are `stateDiagram-v2` and `stateDiagram`. Supported forms:
bare IDs, `state "Label" as ID`, `ID: Label`, `A --> B: event`, `[*]`,
`state ID <<choice>>`, and nested `state ID {` / `}` composite blocks.
Use `direction LR` (or `TB`, `BT`, `RL`) at the top level. State IDs are global
and unique across scopes. Start/end markers get unique generated IDs and
are reused within their scope. Forks, joins, concurrent regions, state notes
and Mermaid state CSS classes are explicit errors. Per-element colours remain
available through the native constructor and `put_style/3`.

## Entity relationship diagrams

ER diagrams keep attributes and cardinality as structured application data:

```elixir
{:ok, diagram} = Ascii.Diagram.er(
  [%{id: "customer", label: "Customer", attributes: [
      %{name: "id", type: "integer", keys: [:pk]},
      %{name: "email", type: "string", keys: [:uk],
        comment: "Login address", label_color: "#58a6ff"}]},
   %{id: "order", label: "Order", attributes: [
      %{name: "customer_id", type: "integer", keys: [:fk]}]}],
  [%{from: "customer", to: "order", label: "places",
     from_cardinality: :one, to_cardinality: :zero_or_more}],
  direction: :lr
)
```

An entity has `id`, optional `label` and `attributes`. Attributes take `name`,
optional `type`, `keys: [:pk, :fk, :uk]`, optional `comment`, and optional
foreground styles. Attribute names must be unique within each entity.
Headers and attributes occupy separate compartments. Type/name/key text and
comments wrap without truncation. Both relationship ends retain cardinality:
`:one`, `:zero_or_one`, `:one_or_more`, `:zero_or_more`. Defaults are `:one`
at `from` and `:zero_or_more` at `to`. `identifying: true` (default) produces
a solid line; `false` produces a dashed line. ER relationships have distinct
ports so markers do not overwrite each other. Boxes reserve extra interior
space when several relationships connect to the same side. End markers rotate with the
connector. ASCII uses bars, `o` and crow's-foot markers; Unicode uses bars,
`○` and directional wedges. Colours apply to both markers and connector paths.

Mermaid's `erDiagram` accepts entity declarations and aliases (`ID [Label]`),
attribute blocks, `PK` / `FK` / `UK` combinations, quoted attribute comments,
`direction`, identifying `--` and non-identifying `..` relationships, and all
four symbolic cardinalities. For example:

```text
erDiagram
  CUSTOMER ||--o{ ORDER : places
  CUSTOMER {
    integer id PK
    string email UK "Login address"
  }
```

The source subset uses ASCII identifiers for entities and attribute names;
labels and comments support the same Unicode as other diagrams. Word-form
cardinality aliases, ER subgraphs and Markdown labels are explicit errors.
No Ecto dependency or database introspection is required.

## Optional colours for individual elements

Nodes, participants, relationships, messages, boundaries, notes, fragments,
activations, states, entities and ER attributes can carry foreground colours. Omitted colours inherit the
diagram theme, or the output renderer's foreground when no theme is supplied.

| Field | Applies to |
| --- | --- |
| `color` | The element's base foreground |
| `border_color` | Box or boundary borders |
| `label_color` | Labels and relationship text |
| `line_color` | Connector paths, participant lifelines and activation bars |

Values use `Ascii.Ink.color/1`: hex colours or CSS variables with an
optional fallback. Individual overrides take precedence over role colours
in `theme:`. `color: false` on rendering disables both themes and individual
colours. Per-cell background fills are outside the current frame contract.

```elixir
{:ok, diagram} = Ascii.Diagram.flowchart(
  [%{id: "api", label: "API", color: "#58a6ff"},
   %{id: "db", label: "Database", border_color: "#3fb950",
     label_color: "var(--text, #ffffff)"}],
  [%{id: "query", from: "api", to: "db", label: "query", line_color: "#d29922"}]
)

# Also works on parsed Mermaid models. nil clears an override.
{:ok, diagram} = Ascii.Diagram.put_style(diagram, {:node, "api"}, color: "#f85149")
{:ok, diagram} = Ascii.Diagram.put_style(diagram, {:edge, "query"}, label_color: "#ffffff")
```

Targets are `{:node, id}` (including participants and C4 elements),
`{:edge, id}` (including sequence messages), `{:boundary, id}`,
`{:fragment, id}`, `{:note, id}`, `{:activation, id}`, and ER
`{:attribute, entity_id, name}`. Invalid colours
and missing targets return an error. Style changes preserve geometry and
characters. A frame supports at most 256 palette entries, including the
default ink; exceeding that returns `{:error, {:too_many_colors, count}}`.

## Mermaid support

```elixir
source = """
sequenceDiagram
actor U as User
participant A as API
U->>A: request
A->>A: validate
A-->>U: response
"""

{:ok, diagram} = Ascii.Mermaid.parse(source)
{:ok, frame} = Ascii.Mermaid.render(source, charset: :ascii)
```

| Family | Supported source |
| --- | --- |
| Flowchart | Nested `subgraph ID [Title]` / `end`, local `direction`, group endpoints; `flowchart` / `graph`; `TB`, `TD`, `BT`, `LR`, `RL`; bare nodes; `[rectangle]`, `(rounded)`, `{diamond}`; quoted labels; chains; `-->`, `---`, `-.->`; `-->|label|`; semicolon-separated statements; `style ID color:...,stroke:...`; `linkStyle N color:...,stroke:...` |
| Sequence | `sequenceDiagram`; `participant` / `actor`; `as` aliases; implicit participants; `->`, `-->`, `->>`, `-->>`; `+` / `-` activation shortcuts; `activate` / `deactivate`; self calls; `Note left of`, `right of`, `over`; nested `loop`, `alt` / `else`, `opt`, `par` / `and`, `critical` / `option`, `break`, `end` |
| C4 | `C4Context`, `C4Container`, `C4Component`; `Person`, `System`, `Container`, `Component`; `Db` / `Queue` variants; `_Ext` variants; `Rel` with optional technology; nested `Boundary`, `Enterprise_Boundary`, `System_Boundary`, `Container_Boundary` blocks; named foreground arguments on `UpdateElementStyle` / `UpdateRelStyle` |
| State | `stateDiagram-v2` / `stateDiagram`; states and aliases; labelled `-->` transitions; `[*]`; `<<choice>>`; nested composite states; top-level `direction` |
| ER | `erDiagram`; entity aliases and attribute blocks; PK/FK/UK; quoted comments; symbolic cardinality at both ends; solid/dashed identification; `direction`; foreground `style ID` |
| Common | Blank lines; full-line `%%` comments; quoted punctuation; single-cell Unicode labels normalized to NFC |

For C4, Person/System functions take `(id, label, optional_description)`.
Container/Component functions take `(id, label, technology, optional_description)`.
Boundary functions take `(id, label) {` and a closing `}` on its own statement.
Additional optional declaration arguments are not supported. Style statements
follow their targets. Flowchart `color` selects label ink and `stroke` selects
border or connector ink; `linkStyle N` uses a zero-based relationship index.
C4 `UpdateElementStyle(ID, $fontColor="...", $borderColor="...")` also works
for boundaries; `UpdateRelStyle(FROM, TO, $textColor="...", $lineColor="...")`
updates matching relationships. Other CSS properties, background colours,
positional style arguments and layout offsets are explicit errors.

Unsupported syntax returns `{:error, {:syntax, line, column, message}}`.
Line and column identify the rejected statement. This includes flowchart
class definitions/click directives, additional shapes/arrows,
sequence actor creation/destruction, and other Mermaid diagram families.
Mermaid's SVG positions, CSS and browser interactions are not reproduced.
See the official [flowchart](https://mermaid.js.org/syntax/flowchart.html),
[sequence](https://mermaid.js.org/syntax/sequenceDiagram.html) and
[C4](https://mermaid.js.org/syntax/c4.html),
[state](https://mermaid.js.org/syntax/stateDiagram.html) and
[ER](https://mermaid.js.org/syntax/entityRelationshipDiagram.html) references for the full languages;
Mermaid currently describes its C4 syntax as experimental.

## Compile once, draw and inspect

```elixir
{:ok, layout} = Ascii.Mermaid.compile("flowchart LR\nA[Request] --> B[Worker]")
{:ok, frame} = Ascii.Diagram.Layout.frame(layout,
  theme: %{node: "#58a6ff", edge: "#8b949e", label: "var(--text, #ffffff)"}
)

%{x: x, y: y} = layout.nodes["A"]
{:node, "A"} = Ascii.Diagram.Layout.hit_at(layout, x + 1, y + 1)
svg = Ascii.Render.SVG.render(frame, title: layout.description)
```

A layout retains `nodes`, `boundaries`, `fragments`, `notes`, `activations`, and ordered `edges` with orthogonal
`points`. Hit testing returns `{:node, id}`, `{:edge, id}`, `{:boundary, id}`,
`{:fragment, id}`, `{:note, id}`, `{:activation, id}`,
`{:attribute, entity_id, name}` or `nil`. Nodes and notes
use bounding rectangles; edge labels and fragment separators are also targets.
Shared source and target channels join deliberately. Unrelated paths crossing are shown with `x` / `╳`, rather than implying a
joined relationship. IDs remain distinct even when labels are identical.

`Layout.frame/2` reuses geometry without parsing or placement. Themes map
`:node`, `:label`, `:edge`, `:edge_label`, `:boundary`, `:lifeline`, `:fragment`,
`:note`, `:activation` to inks
accepted by `Ascii.Ink.color/1`. Themes and `charset: :ascii | :unicode`
do not change geometry. `color: false` emits a monochrome frame.

## Viewports, selection and hit testing

A viewport draws a window into compiled geometry, allocating its own cell
buffer rather than rendering and cropping a complete frame. Its dimensions
are exact; areas beyond the diagram are padded with uncoloured spaces. There
is no reflow or whitespace compaction inside the window.

```elixir
alias Ascii.Diagram.{Layout, Viewport}

{:ok, layout} = Ascii.Mermaid.compile("flowchart LR\nA[Request] --> B[Worker]")
{:ok, selected} = Layout.put_style(layout, {:node, "B"}, border_color: "#58a6ff")
{:ok, viewport} = Layout.viewport(selected, x: 0, y: 0, cols: 80, rows: 24)
{:ok, frame} = Viewport.frame(viewport)
{:ok, viewport} = Viewport.pan(viewport, 12, 0)
{:ok, next_frame} = Viewport.frame(viewport)
changes = Ascii.Frame.changes(frame, next_frame)

# Input coordinates are relative to the window.
target = Viewport.hit_at(viewport, 10, 5)
layout_cell = Viewport.to_layout(viewport, 10, 5)
window_cell = Viewport.to_viewport(viewport, 22, 5)
```

Origins must be non-negative. `pan/3` takes signed deltas and clamps at zero;
panning past the diagram's end shows padding. Coordinate translation returns
`nil` outside the window, and padded cells have no hit target. ER attribute
rows have their own `{:attribute, entity_id, name}` targets. Composite state
borders use `{:boundary, id}`.

`Layout.put_style/3` updates compiled drawing commands without changing node
bounds, edge routes or characters. The existing role themes and `color: false`
also work on viewports. For temporary selection, retain the original layout
and derive a highlighted copy; clearing an override with `nil` restores theme
inheritance. Consumers own cursor, selection, scrolling and update timing.
All frame adapters can consume the resulting window, including ANSI, SVG,
Phoenix and ExRatatui. Rebuild geometry when application data changes; panning
and highlighting reuse the compiled layout.

Viewport limits are 2000 columns, 1000 rows and 200,000 cells. `Viewport.frame/2`
accepts rendering options, including optional narrower `max_cols` / `max_rows`.
The original diagram still obeys its compilation limits; when necessary,
compile with larger `max_cols` / `max_rows` before creating a small viewport.

## Live consumers

Rebuild a model from new application data, or compile revised Mermaid source,
when the data changes. Assign the resulting frame to a LiveView:

```heex
<Ascii.Phoenix.Components.frame frame={@diagram_frame} label={@diagram_label} />
```

The component sends changed rows. A consumer sending cells can use
`Ascii.Frame.changes/2` or `Ascii.Render.ANSI.changes/2`; a resize
requires replacing the displayed frame. An ExRatatui app can place a frame
using `Ascii.ExRatatui.place/3` like any other frame.

Individual style changes can change the palette. `Frame.changes/2` returns
whole rows when palettes differ; consumers transmitting palette indices must
also send the new palette. The Phoenix frame component and ANSI renderer
resolve colours from each current frame.

Native diagrams use this direct model/layout API. The slug registry and
`Ascii.Player` continue to take pieces. Consumers own update timing and
interaction; compile outside a TUI render callback and retain the layout for
hit testing. Syntax errors can be displayed while retaining the last valid
frame.

## Limits and sizing

Inputs are validated, with no silent truncation or user-created atoms:

- Source: 64 KiB and at most 256 non-comment statements, including the header.
- Models: 64 flowchart/C4/state/ER elements, 32 sequence participants, 128 edges or
  sequence events (counting all nested events), and 16 boundaries/groups/composite
  states. ER entities allow up to 64 attributes each and 512 attributes total;
  attribute names and types are single-line text of at most 128 bytes. Fragment
  nesting is limited to eight levels, with at most 16 extra branches per block.
  IDs are unique per record collection or sequence event tree, 1–128 characters,
  matching `[A-Za-z_][A-Za-z0-9_-]*`.
- Labels: up to 4096 bytes, normalized to NFC. Latin accents, Greek, Cyrillic
  and other single-cell Unicode characters are accepted. Control characters,
  residual combining marks, wide/fullwidth characters and emoji are rejected.
  Wide/fullwidth classification uses Unicode 17.0.0 EastAsianWidth data;
  ambiguous-width characters are treated as one cell. `charset: :ascii` changes
  drawing glyphs, and preserves Unicode labels. Wide text needs a display-width
  contract shared by the output adapters.
- Layout: `label_width: 24`, `gap_cols: 8`, `gap_rows: 3`, `max_cols: 400`,
  `max_rows: 200` by default. Routes may reserve more space than the requested
  gaps. Labels wrap at spaces, moving whole words to the next line. Explicit
  newlines and blank lines are retained; words wider than `label_width` split
  by character count without truncation.
- Outputs: at most 200,000 cells; configurable maxima up to 2000 columns and
  1000 rows. An oversized result returns `{:error, {:too_large, {cols, rows}}}`
  before allocating its frame. There is no automatic cropping.

For a larger graph, pass `max_cols:` / `max_rows:` to layout and drawing.
Changing layout options requires laying out again; changing theme or character
set requires only drawing again. Models with invalid keys, duplicate IDs or
missing endpoints return `{:error, {:invalid_diagram, detail}}`.

Run `mise exec -- mix run examples/diagrams.exs` to inspect all five families and a highlighted, panned viewport.
Add `--color` to show their optional element colours in an ANSI terminal.
