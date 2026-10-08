defmodule AsciiArt.OptionsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AsciiArt.{Meta, Options}

  @meta %Meta{
    name: "test",
    category: :ui,
    note: "a test",
    cols: 10,
    rows: 2,
    fps: 0,
    options: %{
      speed: 1,
      labels: true,
      title: "hello",
      names: [],
      phrases: ["a", "b"],
      hour: nil,
      datasets: [%{name: "one", values: [1, 2]}, %{name: "two", values: [3, 4]}],
      series: [%{label: "cpu", lo: 0}, %{label: "mem", lo: 1.2, digits: 1}],
      flights: [["14:05", "lisbon"]]
    },
    bounds: %{speed: {0, 10}}
  }

  test "no options gives the defaults" do
    assert Options.cast(@meta, %{}) == {:ok, @meta.options}
    assert Options.cast(@meta, []) == {:ok, @meta.options}
  end

  test "atom and string keys both reach the option, and override the default" do
    assert {:ok, %{speed: 2, title: "hi"}} = Options.cast(@meta, %{"speed" => 2, title: "hi"})
    assert {:ok, %{speed: 3}} = Options.cast(@meta, speed: 3)
  end

  test "an unknown key is an error, and never becomes an atom" do
    key = "no_such_option_#{System.unique_integer([:positive])}"
    assert Options.cast(@meta, %{key => 1}) == {:error, {:invalid_option, key}}
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    assert Options.cast(@meta, %{nope: 1}) == {:error, {:invalid_option, :nope}}
  end

  test "a value of the wrong shape is an error" do
    assert Options.cast(@meta, %{speed: "fast"}) == {:error, {:invalid_option, :speed}}
    assert Options.cast(@meta, %{labels: 1}) == {:error, {:invalid_option, :labels}}
    assert Options.cast(@meta, %{title: 5}) == {:error, {:invalid_option, :title}}
    assert Options.cast(@meta, %{phrases: [1, 2]}) == {:error, {:invalid_option, :phrases}}
    assert Options.cast(@meta, %{phrases: "x"}) == {:ok, Map.put(@meta.options, :phrases, ["x"])}
  end

  test "strings from params are cast where the default is a number or a boolean" do
    assert {:ok, %{speed: 2.5, labels: false}} =
             Options.cast(@meta, %{"speed" => "2.5", "labels" => "false"})

    assert {:ok, %{speed: 4}} = Options.cast(@meta, %{"speed" => "4"})
  end

  test "numbers are clamped to the piece's bounds, or to a million" do
    assert {:ok, %{speed: 10}} = Options.cast(@meta, %{speed: 1_000})
    assert {:ok, %{speed: 0}} = Options.cast(@meta, %{speed: -3})
    assert {:ok, %{hour: 1.0e6}} = Options.cast(@meta, %{hour: 1.0e300})
  end

  test "a nil default takes nil or a number" do
    assert {:ok, %{hour: 7}} = Options.cast(@meta, %{hour: 7})
    assert {:ok, %{hour: nil}} = Options.cast(@meta, %{hour: nil})
    assert Options.cast(@meta, %{hour: "x"}) == {:error, {:invalid_option, :hour}}
  end

  test "strings and lists are cut to 256" do
    {:ok, %{title: title}} = Options.cast(@meta, %{title: String.duplicate("é", 1000)})
    assert String.length(title) == 256
    {:ok, %{phrases: phrases}} = Options.cast(@meta, %{phrases: List.duplicate("a", 1000)})
    assert length(phrases) == 256
  end

  test "invalid UTF-8 is rejected" do
    assert Options.cast(@meta, %{title: <<0xFF, 0xFE>>}) == {:error, {:invalid_option, :title}}
  end

  test "an empty default list takes strings" do
    assert {:ok, %{names: ["dots"]}} = Options.cast(@meta, %{"names" => ["dots"]})
  end

  test "lists of maps take only keys some default entry has, in any form" do
    assert {:ok, %{datasets: [%{name: "x", values: [5]}]}} =
             Options.cast(@meta, %{"datasets" => [%{"name" => "x", "values" => [5]}]})

    assert {:ok, %{series: [%{label: "net", digits: 2}]}} =
             Options.cast(@meta, %{series: [%{"label" => "net", "digits" => 2}]})

    assert Options.cast(@meta, %{datasets: [%{"evil" => 1}]}) ==
             {:error, {:invalid_option, :datasets}}
  end

  test "lists of lists" do
    assert {:ok, %{flights: [["15:00", "oslo"]]}} =
             Options.cast(@meta, %{flights: [["15:00", "oslo"]]})
  end

  test "JSON text is read where the default is a list" do
    assert {:ok, %{phrases: ["x", "y"]}} = Options.cast(@meta, %{"phrases" => ~s(["x", "y"])})
  end

  property "whatever comes in, the result is the defaults' shape or an error" do
    check all(
            key <- one_of([string(:printable), member_of(Map.keys(@meta.options))]),
            value <- term()
          ) do
      case Options.cast(@meta, %{key => value}) do
        {:ok, options} -> assert Map.keys(options) == Map.keys(@meta.options)
        {:error, {:invalid_option, ^key}} -> :ok
      end
    end
  end
end
