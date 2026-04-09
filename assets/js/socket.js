import {Socket} from "phoenix"

let socket = new Socket("/ws", {params: {}})
socket.connect()

export default socket
