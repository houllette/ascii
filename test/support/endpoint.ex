defmodule Ascii.Test.Endpoint do
  @moduledoc false
  # Just enough of an app for Phoenix.LiveViewTest to mount PlayerLive.
  use Phoenix.Endpoint, otp_app: :ascii

  socket("/live", Phoenix.LiveView.Socket)
end
