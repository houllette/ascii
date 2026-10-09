defmodule Ascii.Diagram.DrawingTest do
  use ExUnit.Case, async: true

  alias Ascii.Diagram.Drawing

  test "labels move whole words to the next line" do
    assert Drawing.wrap("Parse request", 12) == ["Parse", "request"]
    assert Drawing.wrap("Run agent loop", 12) == ["Run agent", "loop"]
    assert Drawing.wrap("Render response", 12) == ["Render", "response"]
    assert Drawing.wrap("one two three four", 7) == ["one two", "three", "four"]
  end

  test "spaces at the width boundary do not create extra or indented lines" do
    assert Drawing.wrap("Parse request", 5) == ["Parse", "reque", "st"]
    assert Drawing.wrap("one   two", 5) == ["one", "two"]
    assert Drawing.wrap("one  two", 8) == ["one  two"]
    assert Drawing.wrap("  one two", 6) == ["  one", "two"]
    assert Drawing.wrap("    Parse request", 8) == ["Parse", "request"]
    assert Drawing.wrap("        ", 4) == ["    ", "    "]
  end

  test "explicit newlines and blank lines are retained" do
    assert Drawing.wrap("\nParse request\n\nDone\n", 12) == [
             "",
             "Parse",
             "request",
             "",
             "Done",
             ""
           ]

    assert Drawing.wrap("", 4) == [""]
  end

  test "overlong words split without losing text and later words wrap normally" do
    assert Drawing.wrap("Go abcdefghijk next", 6) == ["Go", "abcdef", "ghijk", "next"]
    assert Drawing.wrap("abcdefghijkl", 6) == ["abcdef", "ghijkl"]
    assert Drawing.wrap("abcdefghijkl end", 6) == ["abcdef", "ghijkl", "end"]
  end

  test "single-cell Unicode wraps at words and counts cells rather than bytes" do
    assert Drawing.wrap("Café Δοκιμή Привет €", 8) == ["Café", "Δοκιμή", "Привет €"]
    assert Drawing.wrap("Δοκιμή", 4) == ["Δοκι", "μή"]
  end
end
