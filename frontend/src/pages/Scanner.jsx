import { useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { scanORB, scanDaily } from '../api/scanner'

const MOCK_ORB = [
  { ticker: 'TSLA', setup: 'ORB', signal: 'BREAKOUT', orb_pct: 2.3, volume: '12.4M', status: 'TRIGGERED' },
  { ticker: 'NVDA', setup: 'ORB', signal: 'WAITING', orb_pct: 1.1, volume: '8.7M', status: 'WAITING' },
  { ticker: 'AAPL', setup: 'ORB', signal: 'WAITING', orb_pct: 0.8, volume: '5.2M', status: 'WAITING' },
  { ticker: 'AMD',  setup: 'ORB', signal: 'EXPIRED',  orb_pct: 3.5, volume: '9.1M', status: 'EXPIRED' },
]

const MOCK_PREMARKET = [
  { ticker: 'AMZN', setup: 'GAP-UP', signal: 'WATCH', orb_pct: 4.2, volume: '2.1M', status: 'WAITING' },
  { ticker: 'META', setup: 'GAP-DOWN', signal: 'WATCH', orb_pct: -1.8, volume: '1.4M', status: 'WAITING' },
]

const signalColor = (s) => {
  if (s === 'BREAKOUT' || s === 'TRIGGERED') return 'text-emerald-400'
  if (s === 'EXPIRED') return 'text-red-400'
  return 'text-yellow-400'
}

export default function Scanner() {
  const [tab, setTab] = useState('orb')
  const [rows, setRows] = useState(MOCK_ORB)
  const [loading, setLoading] = useState(false)
  const [lastScan, setLastScan] = useState(null)
  const navigate = useNavigate()

  const handleScan = useCallback(async () => {
    setLoading(true)
    try {
      const fn = tab === 'orb' ? scanORB : scanDaily
      const data = await fn()
      const results = Array.isArray(data) ? data : (data.results ?? data.tickers ?? [])
      setRows(results.length ? results : (tab === 'orb' ? MOCK_ORB : MOCK_PREMARKET))
      setLastScan(new Date().toLocaleTimeString())
    } catch {
      setRows(tab === 'orb' ? MOCK_ORB : MOCK_PREMARKET)
      setLastScan(new Date().toLocaleTimeString() + ' (mock)')
    } finally {
      setLoading(false)
    }
  }, [tab])

  const displayRows = rows.length ? rows : (tab === 'orb' ? MOCK_ORB : MOCK_PREMARKET)

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold text-gray-100">Market Scanner</h1>
        <div className="flex items-center gap-4">
          {lastScan && (
            <span className="text-xs text-gray-500 font-mono">Last scan: {lastScan}</span>
          )}
          <button
            onClick={handleScan}
            disabled={loading}
            className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white text-sm font-semibold rounded-md transition-colors"
          >
            {loading ? (
              <>
                <span className="animate-spin">⟳</span> Scanning…
              </>
            ) : (
              '⚡ Scan Now'
            )}
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-gray-900 p-1 rounded-lg w-fit border border-gray-800">
        {[{ key: 'orb', label: 'Opening Range (ORB)' }, { key: 'premarket', label: 'Pre-Market' }].map(t => (
          <button
            key={t.key}
            onClick={() => { setTab(t.key); setRows([]) }}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-colors ${
              tab === t.key
                ? 'bg-emerald-700 text-white'
                : 'text-gray-400 hover:text-gray-200'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Table */}
      <div className="bg-gray-900 border border-gray-700 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-700 bg-gray-800/50">
              <th className="text-left px-4 py-3 text-gray-400 font-medium">Ticker</th>
              <th className="text-left px-4 py-3 text-gray-400 font-medium">Setup</th>
              <th className="text-left px-4 py-3 text-gray-400 font-medium">Signal</th>
              <th className="text-right px-4 py-3 text-gray-400 font-medium">ORB%</th>
              <th className="text-right px-4 py-3 text-gray-400 font-medium">Volume</th>
              <th className="text-center px-4 py-3 text-gray-400 font-medium">Action</th>
            </tr>
          </thead>
          <tbody>
            {displayRows.map((row, i) => (
              <tr
                key={row.ticker + i}
                className="border-b border-gray-800 hover:bg-gray-800/30 transition-colors"
              >
                <td className="px-4 py-3 font-mono font-bold text-emerald-400">{row.ticker}</td>
                <td className="px-4 py-3 text-gray-300">{row.setup}</td>
                <td className={`px-4 py-3 font-semibold ${signalColor(row.signal ?? row.status)}`}>
                  {row.signal ?? row.status}
                </td>
                <td className={`px-4 py-3 font-mono text-right ${
                  parseFloat(row.orb_pct) >= 0 ? 'text-emerald-400' : 'text-red-400'
                }`}>
                  {row.orb_pct != null ? `${parseFloat(row.orb_pct).toFixed(2)}%` : '—'}
                </td>
                <td className="px-4 py-3 font-mono text-right text-gray-300">{row.volume ?? '—'}</td>
                <td className="px-4 py-3 text-center">
                  <button
                    onClick={() => navigate(`/entry/${row.ticker}`)}
                    className="px-3 py-1 bg-gray-700 hover:bg-emerald-700 text-xs font-semibold rounded transition-colors"
                  >
                    Watch →
                  </button>
                </td>
              </tr>
            ))}
            {!displayRows.length && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                  No results — click Scan Now
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
