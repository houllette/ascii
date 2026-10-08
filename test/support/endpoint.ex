defmodule AsciiArt.Test.Endpoint do
  @moduledoc false
  # Just enough of an app for Phoenix.LiveViewTest to mount PlayerLive.
  use Phoenix.Endpoint, otp_app: :ascii_art

  socket("/live", Phoenix.LiveView.Socket)
end
