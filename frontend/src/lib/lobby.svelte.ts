import { Presence, type Channel } from 'phoenix'
import { getSocket } from './socket'
import type { TableSummary } from './types'

/** Live list of public tables and the number of players online. */
export class LobbyConnection {
  tables = $state<TableSummary[]>([])
  online = $state(0)

  private channel: Channel

  constructor(token: string) {
    this.channel = getSocket(token).channel('lobby', {})
    const presence = new Presence(this.channel)
    presence.onSync(() => {
      this.online = presence.list().length
    })

    this.channel.on('table_updated', (summary: TableSummary) => {
      const rest = this.tables.filter((t) => t.code !== summary.code)
      this.tables = [summary, ...rest].sort((a, b) => b.created_at.localeCompare(a.created_at))
    })

    this.channel.on('table_closed', ({ code }: { code: string }) => {
      this.tables = this.tables.filter((t) => t.code !== code)
    })

    this.channel.join().receive('ok', ({ tables }: { tables: TableSummary[] }) => (this.tables = tables))
  }

  leave() {
    this.channel.leave()
  }
}
