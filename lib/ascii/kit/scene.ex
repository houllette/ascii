defmodule Ascii.Kit.Scene do
  @moduledoc """
  The shading helpers every upstream scene defines, word for word: `clamp`,
  `smooth` (smoothstep from `a` to `b`), `mix`, and value noise and fBm over
  `Ascii.Kit.Hash.scene/2`.

  `clamp/1`, `smooth/3` and `mix/3` run for nearly every cell of every
  frame, and a call to another module cannot be inlined, so a scene that
  uses them in its frame keeps local copies with `@compile :inline`, as each
  upstream scene keeps its own; these are the reference, and serve `init`.

  `noise/3` wraps every `period` lattice cells in x when `period` is not 0;
  with 0 it is the scenes' two-argument `noise`, and `fbm/4` with period 0
  their three-argument `fbm`. (desert-night's fBm shifts each octave and
  keeps its own.)
  """

  alias Ascii.JSMath
  alias Ascii.Kit.Hash

  @doc "`v < 0 ? 0 : v > 1 ? 1 : v`."
  @spec clamp(v :: number()) :: number()
  def clamp(v) when v < 0, do: 0
  def clamp(v) when v > 1, do: 1
  def clamp(v), do: v

  @doc "Smoothstep from `a` to `b`: `k = clamp((v - a) / (b - a)); k * k * (3 - 2 * k)`."
  @spec smooth(a :: number(), b :: number(), v :: number()) :: number()
  def smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  @doc "`a + (b - a) * k`."
  @spec mix(a :: number(), b :: number(), k :: number()) :: number()
  def mix(a, b, k), do: a + (b - a) * k

  @doc "Value noise, wrapping every `period` lattice cells in x when `period` is not 0."
  @spec noise(x :: number(), y :: number(), period :: number()) :: float()
  def noise(x, y, period \\ 0) do
    xi = floor(x)
    yi = floor(y)
    fx = x - xi
    fy = y - yi
    u = fx * fx * (3 - 2 * fx)
    v = fy * fy * (3 - 2 * fy)

    {x0, x1} =
      if period != 0 do
        x0 = JSMath.mod(JSMath.mod(xi, period) + period, period)
        {x0, JSMath.mod(x0 + 1, period)}
      else
        {xi, xi + 1}
      end

    a = Hash.scene(x0, yi)
    b = Hash.scene(x1, yi)
    c = Hash.scene(x0, yi + 1)
    d = Hash.scene(x1, yi + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  @doc "Fractal noise: `octaves` of `noise/3`, each twice the frequency and half the weight."
  @spec fbm(x :: number(), y :: number(), octaves :: pos_integer(), period :: number()) :: float()
  def fbm(x, y, octaves, period \\ 0), do: fbm(x, y, octaves, period, 0, 0, 0.5, 1)

  defp fbm(_x, _y, 0, _period, s, n, _amp, _f), do: s / n

  defp fbm(x, y, octaves, period, s, n, amp, f),
    do:
      fbm(
        x,
        y,
        octaves - 1,
        period,
        s + amp * noise(x * f, y * f, period * f),
        n + amp,
        amp * 0.5,
        f * 2
      )
end
