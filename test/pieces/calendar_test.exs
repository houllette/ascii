defmodule AsciiArt.Pieces.CalendarTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Calendar
  use AsciiArt.GoldenCase, slug: "calendar", piece: AsciiArt.Pieces.Calendar
end
