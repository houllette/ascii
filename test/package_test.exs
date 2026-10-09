defmodule Ascii.PackageTest do
  use ExUnit.Case, async: true

  test "the OTP application owns the public Ascii modules" do
    assert Mix.Project.config()[:app] == :ascii
    assert {:ok, modules} = :application.get_key(:ascii, :modules)
    assert Ascii in modules
    assert Ascii.Frame in modules
    assert Ascii.Mermaid in modules
    refute Enum.any?(modules, &String.starts_with?(Atom.to_string(&1), "Elixir.AsciiArt"))
  end

  test "the browser hook lives in the application's packaged static assets" do
    path = Application.app_dir(:ascii, "priv/static/ascii_hook.js")
    assert File.regular?(path)
    assert File.read!(path) =~ "export const Ascii ="
    assert "priv/static/ascii_hook.js" in Mix.Project.config()[:package][:files]
  end
end
