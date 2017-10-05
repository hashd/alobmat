# Moth

## About

This is an open source realtime game server to host games of tambola. An average machine can host upto 100 thousands of games in under 16GB of RAM at the moment with over a million concurrent users connected across the number of games.

## Setup

To start Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.create && mix ecto.migrate`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](http://www.phoenixframework.org/docs/deployment).
