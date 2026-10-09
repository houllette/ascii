defmodule Ascii.Diagram.Sequence do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Layout, Style}

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t()
  def layout(data, opts) do
    depth = depth(data.messages)
    label_space = max(opts[:label_width] + 4, activation_depth(data.messages, %{}, 0) * 2 + 4)

    margin =
      if has_notes?(data.messages),
        do: label_space + depth * 2 + 2,
        else: if(depth > 0, do: depth * 2 + 2, else: 0)

    participants =
      Enum.map(data.participants, &Drawing.node(Map.put(&1, :shape, :rectangle), opts))

    tallest = participants |> Enum.map(& &1.height) |> Enum.max()

    {nodes, right} =
      Enum.reduce(participants, {%{}, margin}, fn node, {nodes, x} ->
        {Map.put(nodes, node.id, Map.merge(node, %{x: x, y: 0})),
         x + node.width + max(opts[:gap_cols], label_space)}
      end)

    state = %{
      nodes: nodes,
      edges: [],
      fragments: %{},
      activations: %{},
      notes: %{},
      active: %{},
      row: tallest + 2,
      last_y: nil,
      width: right + depth * 2 + 2,
      opts: opts,
      label_space: label_space
    }

    state = visit(data.messages, state, 0)
    state = close_open(state)
    edges = Enum.reverse(state.edges)
    extras = Map.merge(state.fragments, state.notes) |> Map.merge(state.activations)
    {cols, rows} = Drawing.extent(nodes, edges, extras)
    rows = max(rows, state.row)

    lifelines =
      Enum.map(participants, fn p ->
        n = nodes[p.id]
        {:lifeline, n.x + div(n.width, 2), n.height, rows - 1, Style.ink(n, :lifeline)}
      end)

    fragments = state.fragments |> Map.values() |> Enum.sort_by(&(-&1.width * &1.height))

    borders =
      Enum.flat_map(fragments, fn f ->
        [
          {:fragment, f}
          | Enum.map(f.dividers, fn {y, label} ->
              {:divider, f.x, f.x + f.width - 1, y, label, f}
            end)
        ]
      end)

    bars =
      state.activations
      |> Map.values()
      |> Enum.sort_by(&{&1.y, &1.x})
      |> Enum.map(&{:activation, &1})

    boxes = Enum.map(participants, &Drawing.box(nodes[&1.id]))

    notes =
      state.notes |> Map.values() |> Enum.sort_by(& &1.y) |> Enum.map(&Drawing.box(&1, :note))

    paths = Enum.map(edges, &Drawing.path/1)
    labels = Enum.flat_map(edges, &Drawing.edge_label/1)

    %Layout{
      cols: cols,
      rows: rows,
      nodes: nodes,
      edges: edges,
      fragments: state.fragments,
      activations: state.activations,
      notes: state.notes,
      commands: lifelines ++ borders ++ bars ++ paths ++ boxes ++ notes ++ labels,
      description: "sequence: #{length(participants)} participants, #{length(edges)} messages"
    }
  end

  defp visit(events, state, depth), do: Enum.reduce(events, state, &event(&1, &2, depth))

  defp event(%{from: from, to: to} = edge, state, _depth) do
    lines = Drawing.wrap(edge.label, state.opts[:label_width])
    sx = center(state.nodes[from])
    ex = center(state.nodes[to])
    y = state.row + length(lines)

    {points, x, height} =
      if sx == ex do
        {[{sx, y}, {sx + state.label_space, y}, {sx + state.label_space, y + 2}, {sx, y + 2}],
         sx + 2, 5}
      else
        {[{sx, y}, {ex, y}], min(sx, ex) + 2, 3}
      end

    edge =
      Map.merge(edge, %{points: points, y: y, label_x: x, label_y: state.row, label_lines: lines})

    %{state | edges: [edge | state.edges], row: state.row + length(lines) + height, last_y: y}
  end

  defp event(%{events: children} = fragment, state, depth) do
    top = state.row
    header = Atom.to_string(fragment.kind) <> " " <> fragment.label
    header_lines = Drawing.wrap(header, state.opts[:label_width])
    state = visit(children, %{state | row: top + length(header_lines) + 2}, depth + 1)

    {state, dividers} =
      Enum.reduce(fragment.branches, {state, []}, fn branch, {state, dividers} ->
        label = branch_prefix(fragment.kind) <> " " <> branch.label
        label_lines = Drawing.wrap(label, state.opts[:label_width])
        y = state.row
        state = visit(branch.events, %{state | row: y + length(label_lines) + 2}, depth + 1)
        {state, dividers ++ for({line, row} <- Enum.with_index(label_lines), do: {y + row, line})}
      end)

    box =
      Map.merge(fragment, %{
        x: depth * 2,
        y: top,
        width: state.width - depth * 4,
        height: state.row - top + 1,
        label: header,
        header_lines: header_lines,
        dividers: dividers
      })

    %{state | fragments: Map.put(state.fragments, fragment.id, box), row: state.row + 2}
  end

  defp event(%{kind: :note} = note, state, _depth) do
    box = Drawing.node(Map.put(note, :shape, :rectangle), state.opts)
    centers = Enum.map(note.participants, &center(state.nodes[&1]))

    width =
      if note.position == :over and length(centers) == 2,
        do: max(box.width, Enum.max(centers) - Enum.min(centers) + 4),
        else: box.width

    box = %{box | width: width}
    x = note_x(note.position, centers, box.width)
    box = Map.merge(box, %{x: x, y: state.row})
    %{state | notes: Map.put(state.notes, note.id, box), row: state.row + box.height + 2}
  end

  defp event(%{kind: :activate, participant: id} = activation, state, _depth) do
    stack = Map.get(state.active, id, [])

    styles =
      Map.merge(Map.take(state.nodes[id], Style.fields()), Map.take(activation, Style.fields()))

    box =
      Map.merge(activation, %{
        x: center(state.nodes[id]) - 1 + length(stack) * 2,
        y: state.last_y || state.row,
        width: 3
      })

    box = Map.merge(box, styles)
    %{state | active: Map.put(state.active, id, [box | stack])}
  end

  defp event(%{kind: :deactivate, participant: id}, state, _depth) do
    [box | rest] = state.active[id]
    box = Map.put(box, :height, max(state.row - box.y, 1))

    %{
      state
      | active: Map.put(state.active, id, rest),
        activations: Map.put(state.activations, box.id, box)
    }
  end

  defp close_open(state) do
    activations =
      Enum.reduce(state.active, state.activations, fn {_id, stack}, acc ->
        Enum.reduce(stack, acc, fn box, acc ->
          Map.put(acc, box.id, Map.put(box, :height, max(state.row - box.y, 1)))
        end)
      end)

    %{state | activations: activations}
  end

  defp center(node), do: node.x + div(node.width, 2)
  defp note_x(:left, centers, width), do: Enum.min(centers) - width - 2
  defp note_x(:right, centers, _width), do: Enum.max(centers) + 2
  defp note_x(:over, centers, width), do: div(Enum.min(centers) + Enum.max(centers) - width, 2)
  defp branch_prefix(:par), do: "and"
  defp branch_prefix(:critical), do: "option"
  defp branch_prefix(_kind), do: "else"

  defp depth(events) do
    Enum.map(events, fn
      %{events: children, branches: branches} ->
        1 + Enum.max([depth(children) | Enum.map(branches, &depth(&1.events))])

      _ ->
        0
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp has_notes?(events) do
    Enum.any?(events, fn
      %{kind: :note} ->
        true

      %{events: children, branches: branches} ->
        has_notes?(children) or Enum.any?(branches, &has_notes?(&1.events))

      _ ->
        false
    end)
  end

  defp activation_depth(events, active, maximum) do
    {_active, maximum} =
      Enum.reduce(events, {active, maximum}, fn
        %{kind: :activate, participant: id}, {active, maximum} ->
          level = Map.get(active, id, 0) + 1
          {Map.put(active, id, level), max(maximum, level)}

        %{kind: :deactivate, participant: id}, {active, maximum} ->
          {Map.update!(active, id, &(&1 - 1)), maximum}

        %{events: children, branches: branches}, {active, maximum} ->
          nested =
            Enum.map(
              [children | Enum.map(branches, & &1.events)],
              &activation_depth(&1, active, maximum)
            )

          {active, Enum.max([maximum | nested])}

        _event, state ->
          state
      end)

    maximum
  end
end
