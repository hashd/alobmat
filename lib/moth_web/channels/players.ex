defmodule MothWeb.Players do
  use Phoenix.Presence, otp_app: :moth,
                        pubsub_server: Moth.PubSub
end
