defmodule Ascii.CoverageTest do
  use ExUnit.Case, async: true

  alias Ascii.{GoldenCase, Registry}

  # Every upstream piece is ported: a fixture without a module, a module
  # without a fixture, or a module without its golden test fails here, so no
  # piece is silently skipped.

  test "every upstream piece's fixture has a registered module" do
    missing = GoldenCase.fixture_slugs() -- Registry.slugs()

    assert missing == [],
           "#{length(missing)} pieces have a fixture but no module: #{Enum.join(missing, ", ")}"
  end

  test "every registered module has a fixture" do
    extra = Registry.slugs() -- GoldenCase.fixture_slugs()
    assert extra == [], "registered without a fixture: #{Enum.join(extra, ", ")}"
  end

  test "every registered module has its golden and contract tests" do
    untested =
      for {slug, mod} <- Registry.all(),
          path = "test/pieces/#{String.replace(slug, "-", "_")}_test.exs",
          not tested?(path, slug, mod),
          do: slug

    assert untested == [],
           "no test/pieces/<slug>_test.exs using both cases for: #{Enum.join(untested, ", ")}"
  end

  test "the registry's modules are the pieces in lib/ascii/pieces" do
    files =
      "lib/ascii/pieces/*.ex"
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".ex"))
      |> Enum.sort()

    assert files == Registry.slugs() |> Enum.map(&String.replace(&1, "-", "_")) |> Enum.sort()
  end

  test "there are as many pieces as upstream has" do
    upstream = "tmp/upstream/src/pieces"

    if File.dir?(upstream) do
      count =
        upstream |> File.ls!() |> Enum.count(&(String.ends_with?(&1, ".ts") and &1 != "index.ts"))

      assert length(GoldenCase.fixture_slugs()) == count
    end
  end

  defp tested?(path, slug, mod) do
    case File.read(path) do
      {:ok, source} ->
        mod = Regex.escape(inspect(mod))

        source =~ ~r/Ascii\.ContractCase,\s+piece: #{mod}\b/ and
          source =~ ~r/Ascii\.GoldenCase,\s+slug: "#{slug}",\s+piece: #{mod}\b/

      {:error, _} ->
        false
    end
  end
end
