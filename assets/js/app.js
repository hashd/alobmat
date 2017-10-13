// Brunch automatically concatenates all files in your
// watched paths. Those paths can be configured at
// config.paths.watched in "brunch-config.js".
//
// However, those files will only be executed if
// explicitly imported. The only exception are files
// in vendor, which are never wrapped in imports and
// therefore are always executed.

// Import dependencies
//
// If you no longer want to use a dependency, remember
// to also remove its path from "config.paths.watched".
import "phoenix_html"

// Import local files
//
// Local files can be imported directly using relative
// paths "./socket" or full ones "web/static/js/socket".

import socket from "./socket"
import lorem from 'lorem-ipsum-simple'

console.log(window.userToken)

// Now that you are connected, you can join channels with a topic:
let chatInput         = document.querySelector("#chat-input")
let messagesContainer = document.querySelector("#messages")
let lobby             = socket.channel(`public:lobby`, {})

lobby.on("new_game", ({id: game_id, name}) => {
  console.log(`Game ${game_id} was started with the name: ${name}`)
  let channel = socket.channel(`game:${game_id}`, {token: window.userToken})

  channel.on("pick", payload => {
    console.log(`${game_id} => Pick: ${payload.pick}`)
  })

  channel.on("timer", payload => {
    console.log(`${game_id} => Left: ${payload.remaining}`)
  })

  channel.on("join", payload => {
    console.log("User Join Event: ", payload)
  })

  setInterval(() => channel.push("message", {text: lorem(parseInt(Math.random() * 30))}), 10000);

  channel.on("message", payload => {
    console.log("New message", payload);
  })

  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })
})

lobby.on("end_game", ({id: game_id}) => {
  console.log(`Game ${game_id} has terminated.`)
})

lobby.join()
  .receive("ok", resp => { console.log("Lobby joined, currently running: ", resp)})
  .receive("error", resp => { console.log("Failed to join lobby")})
