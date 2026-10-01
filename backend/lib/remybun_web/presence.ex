defmodule RemybunWeb.Presence do
  use Phoenix.Presence, otp_app: :remybun, pubsub_server: Remybun.PubSub
end
