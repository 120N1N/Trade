import { Outlet, NavLink, useLocation } from 'react-router-dom'
import { useEffect, useState } from 'react'

function MarketStatus() {
  const [time, setTime] = useState('')
  const [status, setStatus] = useState('')

  useEffect(() => {
    const update = () => {
      const now = new Date()
      const et = new Intl.DateTimeFormat('en-US', {
        timeZone: 'America/New_York',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false,
      }).format(now)
      setTime(et + ' ET')

      const etDate = new Date(now.toLocaleString('en-US', { timeZone: 'America/New_York' }))
      const h = etDate.getHours()
      const m = etDate.getMinutes()
      const mins = h * 60 + m
      const day = etDate.getDay()

      if (day === 0 || day === 6) {
        setStatus('CLOSED')
      } else if (mins >= 930 && mins < 960) {
        setStatus('PRE-OPEN')
      } else if (mins >= 570 && mins < 930) {
        setStatus('PRE-MARKET')
      } else if (mins >= 960 && mins < 1200) {
        setStatus('OPEN')
      } else {
        setStatus('CLOSED')
      }
    }
    update()
    const id = setInterval(update, 1000)
    return () => clearInterval(id)
  }, [])

  const colorMap = {
    OPEN: 'text-emerald-400',
    'PRE-OPEN': 'text-yellow-400',
    'PRE-MARKET': 'text-yellow-400',
    CLOSED: 'text-red-400',
  }

  return (
    <div className="flex items-center gap-4 text-sm font-mono">
      <span className={`font-bold ${colorMap[status] ?? 'text-gray-400'}`}>{status}</span>
      <span className="text-gray-400">{time}</span>
    </div>
  )
}

const navItems = [
  { to: '/scanner', label: 'Scanner', icon: '🔍' },
  { to: '/entry', label: 'Entry/Exit', icon: '📈' },
  { to: '/timemachine', label: 'Time Machine', icon: '⏱' },
  { to: '/risk', label: 'Risk/Budget', icon: '🛡' },
]

export default function Layout() {
  const location = useLocation()
  const tickerMatch = location.pathname.match(/\/entry\/([^/]+)/)
  const selectedTicker = tickerMatch ? tickerMatch[1] : null

  return (
    <div className="flex h-screen bg-gray-950 text-gray-100 overflow-hidden">
      {/* Sidebar */}
      <aside className="w-48 bg-gray-900 border-r border-gray-800 flex flex-col shrink-0">
        <div className="p-4 border-b border-gray-800">
          <div className="text-emerald-400 font-bold text-lg tracking-tight">📊 DayTrader</div>
          <div className="text-xs text-gray-500 mt-0.5">Terminal v1.0</div>
        </div>
        <nav className="flex-1 p-2 space-y-1">
          {navItems.map(({ to, label, icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-md text-sm transition-colors ${
                  isActive
                    ? 'bg-emerald-900/40 text-emerald-400 border border-emerald-800/50'
                    : 'text-gray-400 hover:bg-gray-800 hover:text-gray-100'
                }`
              }
            >
              <span>{icon}</span>
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="p-3 border-t border-gray-800 text-xs text-gray-600">
          backend: localhost:8000
        </div>
      </aside>

      {/* Main area */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Top bar */}
        <header className="h-12 bg-gray-900 border-b border-gray-800 flex items-center justify-between px-6 shrink-0">
          <MarketStatus />
          {selectedTicker && (
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500">Ticker:</span>
              <span className="font-mono font-bold text-emerald-400 text-sm bg-emerald-900/30 px-2 py-0.5 rounded border border-emerald-800/50">
                {selectedTicker}
              </span>
            </div>
          )}
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
