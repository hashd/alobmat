# Alobmat

## About

This is an open source realtime game server to host games of tambola. An average machine can host upto 100 thousands of games in under 16GB of RAM at the moment with over a million concurrent users connected across the number of games.

## Prerequisites

This piece of software is written in Elixir using Phoenix Framework, so you'll need to have these setup:

  * [Erlang](http://www.erlang.org)
  * [Elixir](http://elixir-lang.org)
  * [Phoenix Framework](http://phoenixframework.org)
  * [NPM](http://npmjs.com): *To install client side dependencies and run brunch*

## Setup

After you're done with the prerequisites, to start Phoenix server:

  * `cd` into the project folder
  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.create && mix ecto.migrate`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

Few pieces of this open source software is configurable and more about it will be put up soon.
