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

console.log("Loaded")

// Now that you are connected, you can join channels with a topic:
let chatInput         = document.querySelector("#chat-input")
let messagesContainer = document.querySelector("#messages")
let channel           = socket.channel(`game:game1`, {})

channel.on("new_pick", payload => {
  let messageItem = document.createElement("li");
  messageItem.innerText = `Pick: ${payload.pick}`
  messagesContainer.appendChild(messageItem)
})

channel.on("time_to_pick", payload => {
  let messageItem = document.createElement("li");
  messageItem.innerText = `Left: ${payload.remaining}`
  messagesContainer.appendChild(messageItem)
})

channel.join()
  .receive("ok", resp => { console.log("Joined successfully", resp) })
  .receive("error", resp => { console.log("Unable to join", resp) })