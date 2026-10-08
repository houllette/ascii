defmodule AsciiArt.Kit.Rand do
  @moduledoc """
  mulberry32, the seeded PRNG most pieces use, as a value to thread.

  Upstream makes `const rand = mulberry32(seed)` and calls `rand()` wherever
  it needs a number; the order of those calls is the sequence. Here the
  state is passed along: `{x, rand} = Rand.next(rand)`. Calls must happen
  in upstream's order, including those skipped by `&&` and `?:`.
  """

  alias AsciiArt.Int32

  @typedoc "The generator's state."
  @type t :: Int32.int32()

  @doc "A generator seeded as `mulberry32(seed)` seeds it (`seed | 0`)."
  @spec seed(seed :: number()) :: t()
  def seed(seed), do: Int32.to_int32(seed)

  @doc "The next number in [0, 1), and the generator after it."
  @spec next(rand :: t()) :: {float(), t()}
  def next(rand), do: Int32.mulberry32(rand)

  @doc "The next `n` numbers, in order, and the generator after them."
  @spec take(rand :: t(), n :: non_neg_integer()) :: {[float()], t()}
  def take(rand, n), do: Enum.map_reduce(1..n//1, rand, fn _, r -> Int32.mulberry32(r) end)

  @doc "The first number from a fresh generator: `mulberry32(seed)()`."
  @spec first(seed :: number()) :: float()
  def first(seed), do: seed |> Int32.mulberry32() |> elem(0)
end
