defmodule Ascii.Kit.Clock do
  @moduledoc """
  The wall clock for `clock: true` pieces, from `env.now`.

  Upstream reads `Date.now()` and the local time from `Date`. Here `env.now`
  is a `DateTime`, whose own offset says what local time it is, or `nil` for
  the system clock in the system's time zone.
  """

  alias Ascii.Env

  @doc "Milliseconds since the epoch: `Date.now()`."
  @spec now_ms(env :: Env.t()) :: integer()
  def now_ms(%Env{now: nil}), do: System.os_time(:millisecond)
  def now_ms(%Env{now: %DateTime{} = now}), do: DateTime.to_unix(now, :millisecond)

  @doc """
  The local wall time at `ms` milliseconds since the epoch, as `new Date(ms)`
  reads it: in `env.now`'s offset, or the system's time zone.
  """
  @spec local(env :: Env.t(), ms :: number()) :: NaiveDateTime.t()
  def local(%Env{now: nil}, ms) do
    ms = floor(ms)
    {date, time} = :calendar.system_time_to_local_time(ms, :millisecond)
    NaiveDateTime.from_erl!({date, time}, {Integer.mod(ms, 1000) * 1000, 3})
  end

  def local(%Env{now: %DateTime{utc_offset: utc, std_offset: std}}, ms) do
    NaiveDateTime.add(~N[1970-01-01 00:00:00.000], floor(ms) + (utc + std) * 1000, :millisecond)
  end

  @doc "`getDay()`: 0 for Sunday to 6 for Saturday."
  @spec weekday(date :: Date.t() | NaiveDateTime.t()) :: 0..6
  def weekday(date), do: rem(Date.day_of_week(date), 7)
end
