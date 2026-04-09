defmodule MothWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moth,
    pubsub_server: Moth.PubSub
end
