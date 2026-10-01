import type { Channel } from 'phoenix'
import { getSocket } from './socket'
import type { ChatMessage, GameEvent, TableState } from './types'

export type ConnectionStatus = 'connecting' | 'joined' | 'error'

/** Live connection to a `table:<code>` channel. */
export class TableConnection {
  state = $state<TableState | null>(null)
  status = $state<ConnectionStatus>('connecting')
  error = $state<string | null>(null)
  chat = $state<ChatMessage[]>([])
  unread = $state(0)
  /** Incremented on every update so components can react to new events. */
  eventSeq = $state(0)
  lastEvents: GameEvent[] = []

  private channel: Channel

  constructor(code: string, token: string) {
    this.channel = getSocket(token).channel(`table:${code}`, {})

    this.channel.on('update', ({ events, state }: { events: GameEvent[]; state: TableState }) => {
      this.state = state
      this.lastEvents = events
      if (events.length) this.eventSeq++
    })

    this.channel.on('chat', (msg: ChatMessage) => {
      this.chat = [...this.chat.slice(-99), msg]
      this.unread++
    })

    this.channel
      .join()
      .receive('ok', ({ state }: { state: TableState }) => {
        this.state = state
        this.status = 'joined'
        this.error = null
      })
      .receive('error', ({ reason }: { reason: string }) => {
        this.status = 'error'
        this.error = reason
        // Don't keep retrying a table that doesn't exist.
        if (reason === 'not_found') this.channel.leave()
      })
  }

  /** Sends an action. Resolves on `ok`, rejects with the error reason. */
  push(event: string, payload: Record<string, unknown> = {}): Promise<void> {
    return new Promise((resolve, reject) => {
      this.channel
        .push(event, payload, 8000)
        .receive('ok', () => resolve())
        .receive('error', ({ reason }: { reason: string }) => reject(reason))
        .receive('timeout', () => reject('timeout'))
    })
  }

  leave() {
    this.channel.leave()
  }
}
