# mix run tools/gen_registry.exs
#
# Rewrites the @pieces map in lib/ascii_art/registry.ex: every module in
# lib/ascii_art/pieces/, keyed by its upstream slug (the golden fixture's
# name). The registry stays an explicit map in source; this keeps it in step.
fixtures = "test/fixtures/golden"
slugs = fixtures |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> Map.new(&{String.replace(Path.rootname(&1), "-", "_"), Path.rootname(&1)})

entries =
  for file <- "lib/ascii_art/pieces/*.ex" |> Path.wildcard() |> Enum.sort() do
    snake = Path.basename(file, ".ex")
    slug = Map.fetch!(slugs, snake)
    [_, mod] = Regex.run(~r/defmodule (AsciiArt\.Pieces\.\w+) do/, File.read!(file))
    ~s(    "#{slug}" => #{mod})
  end

path = "lib/ascii_art/registry.ex"
source = File.read!(path)
source = Regex.replace(~r/  @pieces %\{.*?\n  \}\n/s, source, "  @pieces %{\n#{Enum.join(entries, ",\n")}\n  }\n")
File.write!(path, source)
IO.puts("#{length(entries)} pieces registered")
