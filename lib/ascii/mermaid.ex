defmodule Ascii.Mermaid do
  @moduledoc """
  Parses a documented subset of Mermaid into native `Ascii.Diagram`s.

  Supports flowcharts, sequences and C4 context/container/component views.
  Unsupported statements are errors, with source line and column; they are
  never silently ignored. This is a character renderer with its own layout,
  rather than pixel or layout parity with Mermaid's SVG output. See the
  [support matrix](guides/diagrams.md#mermaid-support).

      iex> {:ok, frame} = Ascii.Mermaid.render("flowchart LR\\nA[Hello] --> B[World]")
      iex> frame.text =~ "World"
      true
  """

  alias Ascii.Diagram
  alias Ascii.Mermaid.{C4, Flowchart, Sequence, Syntax}

  @type error ::
          Diagram.error()
          | {:error, {:invalid_source, :type | :size | :encoding | :statements}}
          | {:error, {:syntax, pos_integer(), pos_integer(), String.t()}}

  @doc "Parses at most 64 KiB of source, without the piece options' string truncation."
  @spec parse(source :: String.t()) :: {:ok, Diagram.t()} | error()
  def parse(source) when is_binary(source) and byte_size(source) <= 65_536 do
    if String.valid?(source),
      do: parse_statements(Syntax.statements(source)),
      else: {:error, {:invalid_source, :encoding}}
  end

  def parse(source) when is_binary(source), do: {:error, {:invalid_source, :size}}
  def parse(_source), do: {:error, {:invalid_source, :type}}

  defp parse_statements([]), do: Syntax.error({"", 1, 1}, "expected a diagram header")

  defp parse_statements(statements) when length(statements) > 256,
    do: {:error, {:invalid_source, :statements}}

  defp parse_statements([{header, _line, _column} = position | rest]) do
    case header do
      "sequenceDiagram" -> Sequence.parse(rest, position)
      "C4Context" -> C4.parse(rest, :context, position)
      "C4Container" -> C4.parse(rest, :container, position)
      "C4Component" -> C4.parse(rest, :component, position)
      _ -> parse_flowchart(header, position, rest)
    end
  end

  defp parse_flowchart(header, position, rest) do
    case Regex.run(~r/\A(?:flowchart|graph)\s+(TB|TD|BT|LR|RL)\z/, header) do
      [_, direction] -> Flowchart.parse(rest, direction(direction), position)
      _ -> Syntax.error(position, "unsupported diagram header")
    end
  end

  defp direction("LR"), do: :lr
  defp direction("RL"), do: :rl
  defp direction("BT"), do: :bt
  defp direction(_direction), do: :tb

  @doc "Parses and lays out once; retain the layout for repeated drawing or hit testing."
  @spec compile(source :: String.t(), opts :: keyword()) :: {:ok, Diagram.Layout.t()} | error()
  def compile(source, opts \\ []) do
    with {:ok, diagram} <- parse(source), do: Diagram.layout(diagram, opts)
  end

  @doc "Parses and renders source as a standard frame."
  @spec render(source :: String.t(), opts :: keyword()) :: {:ok, Ascii.Frame.t()} | error()
  def render(source, opts \\ []) do
    with {:ok, layout} <- compile(source, opts), do: Diagram.Layout.frame(layout, opts)
  end
end
