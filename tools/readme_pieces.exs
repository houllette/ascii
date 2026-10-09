# mix run tools/readme_pieces.exs
#
# Rewrites the pieces table in README.md (between the <!-- pieces --> marks)
# from the registry: every piece by category, in upstream's category order.
# test/readme_test.exs fails when the table is out of date.
alias Ascii.{Meta, Registry}

by_category = Enum.group_by(Registry.all(), fn {_slug, mod} -> mod.meta().category end)

rows =
  for category <- Meta.categories(), pieces = Map.get(by_category, category, []), pieces != [] do
    names = Enum.map_join(pieces, ", ", fn {slug, _} -> "`#{slug}`" end)
    "| #{category} | #{length(pieces)} | #{names} |"
  end

table = Enum.join(["| category | pieces | slugs |", "| --- | --- | --- |" | rows], "\n")
readme = File.read!("README.md")

updated =
  Regex.replace(~r/<!-- pieces -->.*<!-- \/pieces -->/s, readme, "<!-- pieces -->\n" <> table <> "\n<!-- /pieces -->")

File.write!("README.md", updated)
IO.puts("README.md: #{length(Registry.all())} pieces in #{length(rows)} categories")
