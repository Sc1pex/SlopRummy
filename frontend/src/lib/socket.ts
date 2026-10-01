import { Socket } from 'phoenix'
import { API_URL } from './api'

let socket: Socket | null = null
let socketToken: string | null = null

function socketUrl() {
  if (API_URL) return API_URL.replace(/^http/, 'ws') + '/socket'
  return '/socket'
}

/** The shared socket for the current token, connecting it if needed. */
export function getSocket(token: string): Socket {
  if (socket && socketToken === token) return socket

  disconnectSocket()
  socket = new Socket(socketUrl(), { params: { token } })
  socketToken = token
  socket.connect()
  return socket
}

export function disconnectSocket() {
  socket?.disconnect()
  socket = null
  socketToken = null
}
