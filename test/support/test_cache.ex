defmodule AsciiArt.TestCache do
  @moduledoc """
  Memoizes expensive, pure test inputs (a piece's initial state, a decoded
  fixture) for the whole run, in an ETS table made by `test_helper.exs`.
  """

  @table :ascii_art_test_cache

  @doc false
  def start, do: :ets.new(@table, [:named_table, :public, read_concurrency: true])

  @doc "The value for `key`, computing it with `fun` the first time."
  def fetch(key, fun) do
    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = fun.()
        :ets.insert(@table, {key, value})
        value
    end
  end
end
