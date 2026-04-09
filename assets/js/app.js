// We import the CSS which is extracted to its own file by esbuild
import "../css/app.css"

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"

// Import local files
import socket from "./socket"

console.log(window.userToken)

// Now that you are connected, you can join channels with a topic:
let lobby = socket.channel("public:lobby", {})

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

  channel.on("message", payload => {
    console.log("New message", payload)
  })

  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })
})

lobby.on("end_game", ({id: game_id}) => {
  console.log(`Game ${game_id} has terminated.`)
})

lobby.join()
  .receive("ok", resp => { console.log("Lobby joined, currently running: ", resp) })
  .receive("error", resp => { console.log("Failed to join lobby") })
