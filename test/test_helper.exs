AsciiArt.TestCache.start()
Logger.configure(level: :warning)

Application.put_env(:phoenix, :json_library, JSON)

Application.put_env(:ascii_art, AsciiArt.Test.Endpoint,
  secret_key_base: String.duplicate("ascii_art", 8),
  live_view: [signing_salt: "ascii_art_test"],
  server: false
)

{:ok, _} = AsciiArt.Test.Endpoint.start_link()

# Frame-time budgets run on their own: mix test --only perf
ExUnit.start(exclude: [:perf])
