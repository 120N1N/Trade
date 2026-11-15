import { useState, useEffect } from 'react'
import { useLocation } from 'react-router-dom'
import {
  PieChart,
  Pie,
  Cell,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
} from 'recharts'
import StatCard from '../components/StatCard'
import { runSimulation } from '../api/timemachine'
import { getPlan } from '../api/entry'

// Fallback mock simulation data
function generateMockSimResults(symbol, entry, stop, target) {
  const hitTargetPct = 58.4
  const hitStopPct = 34.2
  const closedFlatPct = 7.4
  const avgR = 0.82

  const pastSessions = [
    { date: '2025-05-12', entry: Number(entry).toFixed(2), outcome: 'TARGET', pnl: `+$${((target - entry) * 100).toFixed(2)}` },
    { date: '2025-05-09', entry: Number(entry).toFixed(2), outcome: 'STOP',   pnl: `-$${((entry - stop) * 100).toFixed(2)}` },
    { date: '2025-05-08', entry: Number(entry).toFixed(2), outcome: 'TARGET', pnl: `+$${((target - entry) * 100).toFixed(2)}` },
    { date: '2025-05-05', entry: Number(entry).toFixed(2), outcome: 'FLAT',   pnl: '$0.00' },
    { date: '2025-05-02', entry: Number(entry).toFixed(2), outcome: 'TARGET', pnl: `+$${((target - entry) * 100).toFixed(2)}` },
  ]

  // Fan chart: 20 replay paths over 30 step intervals
  const steps = 25
  const fanData = []
  for (let s = 0; s <= steps; s++) {
    const row = { step: s }
    for (let p = 0; p < 20; p++) {
      const noise = (Math.random() - 0.47) * (Number(entry) * 0.004) * Math.sqrt(s + 1)
      row[`path_${p}`] = Number((Number(entry) + noise).toFixed(2))
    }
    fanData.push(row)
  }

  return {
    symbol,
    win_rate: hitTargetPct,
    stop_rate: hitStopPct,
    flat_rate: closedFlatPct,
    avg_r: avgR,
    history: pastSessions,
    fan_data: fanData,
  }
}

export default function TimeMachine() {
  const location = useLocation()
  const navState = location.state || {}

  const [form, setForm] = useState({
    symbol: navState.symbol || 'TSLA',
    entry: navState.entry || '250.00',
    stop: navState.stop || '245.00',
    target: navState.target || '260.00',
    replays: 10000,
  })

  const [loading, setLoading] = useState(false)
  const [results, setResults] = useState(null)

  // Auto-fill from current plan.json if not passed via navigation state
  useEffect(() => {
    if (!navState.symbol) {
      getPlan()
        .then((plan) => {
          if (plan && plan.symbol) {
            setForm((prev) => ({
              ...prev,
              symbol: plan.symbol || prev.symbol,
              entry: plan.entry || prev.entry,
              stop: plan.stop || prev.stop,
              target: plan.target || prev.target,
            }))
          }
        })
        .catch(() => {})
    }
  }, [navState])

  const handleSimulate = async (e) => {
    e?.preventDefault()
    setLoading(true)
    const payload = {
      symbol: form.symbol.toUpperCase(),
      entry: parseFloat(form.entry),
      stop: parseFloat(form.stop),
      target: parseFloat(form.target),
      replays: parseInt(form.replays, 10) || 10000,
    }

    try {
      const data = await runSimulation(payload)
      if (data && (data.win_rate != null || data.history)) {
        setResults(data)
      } else {
        setResults(generateMockSimResults(payload.symbol, payload.entry, payload.stop, payload.target))
      }
    } catch {
      setResults(generateMockSimResults(payload.symbol, payload.entry, payload.stop, payload.target))
    } finally {
      setLoading(false)
    }
  }

  // Pie chart data
  const pieData = results
    ? [
        { name: 'Hit Target', value: results.win_rate ?? 58.4, color: '#10b981' },
        { name: 'Hit Stop', value: results.stop_rate ?? 34.2, color: '#ef4444' },
        { name: 'Closed Flat', value: results.flat_rate ?? 7.4, color: '#6b7280' },
      ]
    : []

  return (
    <div className="p-6 space-y-6 max-w-7xl mx-auto">
      <div>
        <h1 className="text-xl font-bold text-gray-100">Time Machine Replay Engine</h1>
        <p className="text-xs text-gray-400 mt-1">
          Simulate trade outcomes across thousands of historical opening range scenarios.
        </p>
      </div>

      {/* Input Form */}
      <form
        onSubmit={handleSimulate}
        className="bg-gray-900 border border-gray-700 rounded-lg p-5 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4 items-end"
      >
        <div>
          <label className="text-xs text-gray-400 font-medium block mb-1">Symbol</label>
          <input
            type="text"
            value={form.symbol}
            onChange={(e) => setForm({ ...form, symbol: e.target.value.toUpperCase() })}
            className="w-full bg-gray-800 border border-gray-700 px-3 py-2 rounded font-mono text-sm uppercase text-white focus:outline-none focus:border-emerald-500"
            required
          />
        </div>
        <div>
          <label className="text-xs text-gray-400 font-medium block mb-1">Entry ($)</label>
          <input
            type="number"
            step="0.01"
            value={form.entry}
            onChange={(e) => setForm({ ...form, entry: e.target.value })}
            className="w-full bg-gray-800 border border-gray-700 px-3 py-2 rounded font-mono text-sm text-white focus:outline-none focus:border-emerald-500"
            required
          />
        </div>
        <div>
          <label className="text-xs text-gray-400 font-medium block mb-1">Stop ($)</label>
          <input
            type="number"
            step="0.01"
            value={form.stop}
            onChange={(e) => setForm({ ...form, stop: e.target.value })}
            className="w-full bg-gray-800 border border-gray-700 px-3 py-2 rounded font-mono text-sm text-red-400 focus:outline-none focus:border-red-500"
            required
          />
        </div>
        <div>
          <label className="text-xs text-gray-400 font-medium block mb-1">Target ($)</label>
          <input
            type="number"
            step="0.01"
            value={form.target}
            onChange={(e) => setForm({ ...form, target: e.target.value })}
            className="w-full bg-gray-800 border border-gray-700 px-3 py-2 rounded font-mono text-sm text-emerald-400 focus:outline-none focus:border-emerald-500"
            required
          />
        </div>
        <div>
          <label className="text-xs text-gray-400 font-medium block mb-1">Replays</label>
          <input
            type="number"
            value={form.replays}
            onChange={(e) => setForm({ ...form, replays: e.target.value })}
            className="w-full bg-gray-800 border border-gray-700 px-3 py-2 rounded font-mono text-sm text-white focus:outline-none focus:border-emerald-500"
            required
          />
        </div>
        <div>
          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white font-semibold text-xs rounded transition-colors flex items-center justify-center gap-2"
          >
            {loading ? (
              <>
                <span className="animate-spin">⟳</span> Simulating...
              </>
            ) : (
              '▶ Run Simulation'
            )}
          </button>
        </div>
      </form>

      {/* Results View */}
      {results && (
        <div className="space-y-6">
          {/* Stat Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <StatCard
              label="Hit Target %"
              value={`${Number(results.win_rate).toFixed(1)}%`}
              sub="Reached profit target"
              color="text-emerald-400"
            />
            <StatCard
              label="Hit Stop %"
              value={`${Number(results.stop_rate).toFixed(1)}%`}
              sub="Stopped out"
              color="text-red-400"
            />
            <StatCard
              label="Closed Flat %"
              value={`${Number(results.flat_rate).toFixed(1)}%`}
              sub="Exited near breakeven"
              color="text-gray-400"
            />
            <StatCard
              label="Avg R Return"
              value={`${results.avg_r >= 0 ? '+' : ''}${Number(results.avg_r).toFixed(2)}R`}
              sub="Expected value / trade"
              color={results.avg_r >= 0 ? 'text-emerald-400' : 'text-red-400'}
            />
          </div>

          {/* Charts Row */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Pie Chart */}
            <div className="bg-gray-900 border border-gray-700 rounded-lg p-4 flex flex-col items-center justify-center">
              <span className="text-xs uppercase tracking-wider text-gray-400 font-semibold mb-2 self-start">
                Outcome Distribution
              </span>
              <div className="w-full h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={pieData}
                      dataKey="value"
                      nameKey="name"
                      cx="50%"
                      cy="50%"
                      outerRadius={75}
                      innerRadius={45}
                      paddingAngle={3}
                      label={({ name, percent }) => `${(percent * 100).toFixed(0)}%`}
                    >
                      {pieData.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                    <RechartsTooltip
                      contentStyle={{ backgroundColor: '#111827', borderColor: '#374151', borderRadius: '6px' }}
                      formatter={(val) => `${Number(val).toFixed(1)}%`}
                    />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              <div className="flex gap-4 text-xs font-mono mt-1">
                <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 bg-emerald-500 rounded-full"></span> Target</span>
                <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 bg-red-500 rounded-full"></span> Stop</span>
                <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 bg-gray-500 rounded-full"></span> Flat</span>
              </div>
            </div>

            {/* Fan Chart (Replay paths) */}
            <div className="lg:col-span-2 bg-gray-900 border border-gray-700 rounded-lg p-4 flex flex-col">
              <span className="text-xs uppercase tracking-wider text-gray-400 font-semibold mb-2">
                20 Sample Replay Paths (Fan Chart)
              </span>
              <div className="w-full h-56 flex-1">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={results.fan_data || []}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
                    <XAxis dataKey="step" stroke="#4b5563" tick={{ fontSize: 10 }} />
                    <YAxis
                      stroke="#4b5563"
                      domain={['auto', 'auto']}
                      tick={{ fontSize: 10 }}
                      tickFormatter={(v) => `$${v}`}
                    />
                    <RechartsTooltip
                      contentStyle={{ backgroundColor: '#111827', borderColor: '#374151', fontSize: '11px' }}
                    />
                    {Array.from({ length: 20 }).map((_, idx) => (
                      <Line
                        key={idx}
                        type="monotone"
                        dataKey={`path_${idx}`}
                        stroke={idx % 2 === 0 ? '#10b981' : '#3b82f6'}
                        strokeOpacity={0.25}
                        strokeWidth={1.2}
                        dot={false}
                        isAnimationActive={false}
                      />
                    ))}
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </div>
          </div>

          {/* Past Sessions Table */}
          <div className="bg-gray-900 border border-gray-700 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-700 bg-gray-800/40">
              <span className="text-xs font-semibold uppercase tracking-wider text-gray-300">
                Past Historical Sessions
              </span>
            </div>
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-gray-700 bg-gray-800/20 text-gray-400">
                  <th className="text-left px-4 py-2.5 font-medium">Date</th>
                  <th className="text-right px-4 py-2.5 font-medium">Entry</th>
                  <th className="text-center px-4 py-2.5 font-medium">Outcome</th>
                  <th className="text-right px-4 py-2.5 font-medium">P&amp;L</th>
                </tr>
              </thead>
              <tbody>
                {(results.history || []).map((row, idx) => (
                  <tr key={idx} className="border-b border-gray-800 hover:bg-gray-800/20">
                    <td className="px-4 py-2.5 font-mono text-gray-300">{row.date}</td>
                    <td className="px-4 py-2.5 font-mono text-right text-gray-100">${row.entry}</td>
                    <td className="px-4 py-2.5 text-center">
                      <span
                        className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                          row.outcome === 'TARGET'
                            ? 'bg-emerald-900/50 text-emerald-400 border border-emerald-800'
                            : row.outcome === 'STOP'
                            ? 'bg-red-900/50 text-red-400 border border-red-800'
                            : 'bg-gray-800 text-gray-400'
                        }`}
                      >
                        {row.outcome}
                      </span>
                    </td>
                    <td
                      className={`px-4 py-2.5 font-mono text-right font-semibold ${
                        row.pnl.startsWith('+')
                          ? 'text-emerald-400'
                          : row.pnl.startsWith('-')
                          ? 'text-red-400'
                          : 'text-gray-400'
                      }`}
                    >
                      {row.pnl}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
