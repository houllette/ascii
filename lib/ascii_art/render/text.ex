defmodule AsciiArt.Render.Text do
  @moduledoc "A frame as plain text: `rows` lines of `cols` characters, no colour."

  alias AsciiArt.Frame

  @doc "The frame's text, as iodata."
  @spec render(frame :: Frame.t()) :: iodata()
  def render(%Frame{text: text}), do: text
end
