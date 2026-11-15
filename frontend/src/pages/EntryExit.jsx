import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import CandlestickChart from '../components/CandlestickChart'
import StatusBadge from '../components/StatusBadge'
import { checkEntry, getRange, getBars, planExit } from '../api/entry'

// Generate sample mock 5m bars for preview when backend is connecting/down
function generateMockBars(basePrice = 250) {
  const bars = []
  let price = basePrice
  const now = Math.floor(Date.now() / 1000)
  for (let i = 40; i >= 0; i--) {
    const time = now - i * 300
    const delta = (Math.random() - 0.48) * (basePrice * 0.006)
    const open = price
    const close = price + delta
    const high = Math.max(open, close) + Math.random() * (basePrice * 0.003)
    const low = Math.min(open, close) - Math.random() * (basePrice * 0.003)
    price = close
    bars.push({ time, open, high, low, close })
  }
  return bars
}

export default function EntryExit() {
  const { ticker: urlTicker } = useParams()
  const navigate = useNavigate()
  const ticker = (urlTicker || 'TSLA').toUpperCase()

  const [inputTicker, setInputTicker] = useState(ticker)
  const [bars, setBars] = useState([])
  const [loadingBars, setLoadingBars] = useState(false)
  const [entryStatus, setEntryStatus] = useState('WAITING')
  const [rangeData, setRangeData] = useState({
    or_high: 252.5,
    or_low: 247.8,
    current_price: 251.2,
    pct_from_high: -0.51,
  })

  // Exit Planner state
  const [entryPrice, setEntryPrice] = useState('251.20')
  const [stopType, setStopType] = useState('or-mid')
  const [targetType, setTargetType] = useState('2R')
  const [planning, setPlanning] = useState(false)
  const [planResult, setPlanResult] = useState(null)

  const fetchData = useCallback(async () => {
    setLoadingBars(true)
    // 1. Fetch Bars
    try {
      const barsRes = await getBars(ticker, '5m')
      const rawBars = Array.isArray(barsRes) ? barsRes : (barsRes.bars || [])
      if (rawBars.length) {
        setBars(rawBars)
      } else {
        setBars(generateMockBars(250))
      }
    } catch {
      setBars(generateMockBars(250))
    } finally {
      setLoadingBars(false)
    }

    // 2. Fetch Entry Status & Range
    try {
      const statusRes = await checkEntry(ticker)
      if (statusRes) {
        setEntryStatus(statusRes.status || statusRes.signal || 'WAITING')
        const current = statusRes.current_price ?? statusRes.price ?? 251.2
        const high = statusRes.or_high ?? 252.5
        const low = statusRes.or_low ?? 247.8
        const pct = statusRes.pct_from_high ?? (((current - high) / high) * 100)
        setRangeData({
          or_high: high,
          or_low: low,
          current_price: current,
          pct_from_high: pct,
        })
        setEntryPrice(Number(current).toFixed(2))
      }
    } catch {
      // Mock defaults
      setEntryStatus('WAITING')
      setRangeData({
        or_high: 252.5,
        or_low: 247.8,
        current_price: 251.2,
        pct_from_high: -0.51,
      })
      setEntryPrice('251.20')
    }
  }, [ticker])

  useEffect(() => {
    setInputTicker(ticker)
    setPlanResult(null)
    fetchData()
  }, [ticker, fetchData])

  const handleTickerSubmit = (e) => {
    e.preventDefault()
    if (inputTicker.trim()) {
      navigate(`/entry/${inputTicker.trim().toUpperCase()}`)
    }
  }

  const handlePlanExit = async (e) => {
    e.preventDefault()
    setPlanning(true)
    const numEntry = parseFloat(entryPrice) || rangeData.current_price
    try {
      const res = await planExit({
        symbol: ticker,
        entry: numEntry,
        or_high: rangeData.or_high,
        or_low: rangeData.or_low,
        stop_type: stopType,
        target_type: targetType,
      })
      setPlanResult(res)
    } catch {
      // Fallback calculation for mock
      const mid = (rangeData.or_high + rangeData.or_low) / 2
      let stop = rangeData.or_low
      if (stopType === 'or-mid') stop = mid
      else if (stopType === 'pct:1') stop = numEntry * 0.99
      else if (stopType === 'pct:2') stop = numEntry * 0.98
      else if (stopType === 'atr:1.5') stop = numEntry - 3.5

      const risk = Math.max(0.1, numEntry - stop)
      let multiplier = 2
      if (targetType === '1R') multiplier = 1
      else if (targetType === '1.5R') multiplier = 1.5
      else if (targetType === '3R') multiplier = 3
      const target = numEntry + risk * multiplier

      setPlanResult({
        symbol: ticker,
        entry: numEntry,
        stop: Number(stop.toFixed(2)),
        target: Number(target.toFixed(2)),
        risk: Number(risk.toFixed(2)),
        rr_ratio: `${multiplier}:1`,
      })
    } finally {
      setPlanning(false)
    }
  }

  // Horizontal Lines for Chart
  const chartLines = [
    { price: rangeData.or_high, color: '#f59e0b', label: 'OR High' },
    { price: rangeData.or_low, color: '#6366f1', label: 'OR Low' },
  ]

  if (planResult) {
    if (planResult.stop) chartLines.push({ price: planResult.stop, color: '#ef4444', label: 'Stop' })
    if (planResult.target) chartLines.push({ price: planResult.target, color: '#10b981', label: 'Target' })
    if (planResult.entry) chartLines.push({ price: planResult.entry, color: '#3b82f6', label: 'Entry' })
  }

  return (
    <div className="h-full flex flex-col p-4 gap-4 overflow-y-auto">
      {/* Top Header Row */}
      <div className="flex flex-wrap items-center justify-between gap-4 bg-gray-900 border border-gray-800 p-4 rounded-lg">
        <form onSubmit={handleTickerSubmit} className="flex items-center gap-3">
          <label className="text-sm text-gray-400 font-medium">Symbol:</label>
          <input
            type="text"
            value={inputTicker}
            onChange={(e) => setInputTicker(e.target.value)}
            className="bg-gray-800 border border-gray-700 px-3 py-1.5 rounded font-mono font-bold text-white uppercase w-28 focus:outline-none focus:border-emerald-500"
          />
          <button
            type="submit"
            className="bg-gray-700 hover:bg-gray-600 text-xs px-3 py-2 rounded font-semibold text-gray-200 transition-colors"
          >
            Load
          </button>
        </form>

        <div className="flex items-center gap-4">
          <button
            onClick={fetchData}
            disabled={loadingBars}
            className="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 border border-gray-700 text-xs text-gray-300 font-mono rounded flex items-center gap-2"
          >
            <span>⟳</span> Refresh 5m Bars
          </button>
        </div>
      </div>

      {/* Main Grid: Left Chart, Right Panels */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 flex-1">
        {/* Left Chart (2 cols) */}
        <div className="lg:col-span-2 bg-gray-900 border border-gray-700 rounded-lg p-4 flex flex-col min-h-[480px]">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-semibold text-gray-300">{ticker} — 5-Minute Intraday Bars</span>
            <div className="flex items-center gap-3 text-xs font-mono">
              <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 bg-yellow-500 rounded-full inline-block"></span> OR High</span>
              <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 bg-indigo-500 rounded-full inline-block"></span> OR Low</span>
              {planResult && (
                <>
                  <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 bg-emerald-500 rounded-full inline-block"></span> Target</span>
                  <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 bg-red-500 rounded-full inline-block"></span> Stop</span>
                </>
              )}
            </div>
          </div>
          <div className="flex-1 w-full relative">
            <CandlestickChart bars={bars} lines={chartLines} />
          </div>
        </div>

        {/* Right Panels (1 col) */}
        <div className="space-y-4 flex flex-col">
          {/* Top Panel: Entry Status */}
          <div className="bg-gray-900 border border-gray-700 rounded-lg p-4 space-y-4">
            <div className="flex items-center justify-between border-b border-gray-800 pb-3">
              <span className="text-xs uppercase tracking-wider text-gray-400 font-semibold">Entry Status</span>
              <button
                onClick={fetchData}
                className="text-xs text-emerald-400 hover:underline flex items-center gap-1"
              >
                ⟳ Check Entry
              </button>
            </div>

            <div className="flex justify-center py-1">
              <StatusBadge status={entryStatus} />
            </div>

            <div className="grid grid-cols-2 gap-3 pt-2 text-sm font-mono">
              <div className="bg-gray-950 p-2.5 rounded border border-gray-800">
                <span className="text-xs text-gray-500 block">Current Price</span>
                <span className="text-base font-bold text-gray-100">${Number(rangeData.current_price).toFixed(2)}</span>
              </div>
              <div className="bg-gray-950 p-2.5 rounded border border-gray-800">
                <span className="text-xs text-gray-500 block">% from OR High</span>
                <span className={`text-base font-bold ${rangeData.pct_from_high >= 0 ? 'text-emerald-400' : 'text-yellow-400'}`}>
                  {rangeData.pct_from_high >= 0 ? '+' : ''}{Number(rangeData.pct_from_high).toFixed(2)}%
                </span>
              </div>
              <div className="bg-gray-950 p-2.5 rounded border border-gray-800">
                <span className="text-xs text-gray-500 block">OR High</span>
                <span className="text-sm font-semibold text-yellow-400">${Number(rangeData.or_high).toFixed(2)}</span>
              </div>
              <div className="bg-gray-950 p-2.5 rounded border border-gray-800">
                <span className="text-xs text-gray-500 block">OR Low</span>
                <span className="text-sm font-semibold text-indigo-400">${Number(rangeData.or_low).toFixed(2)}</span>
              </div>
            </div>
          </div>

          {/* Bottom Panel: Exit Planner */}
          <div className="bg-gray-900 border border-gray-700 rounded-lg p-4 space-y-4 flex-1">
            <div className="border-b border-gray-800 pb-3">
              <span className="text-xs uppercase tracking-wider text-gray-400 font-semibold">Exit Planner</span>
            </div>

            <form onSubmit={handlePlanExit} className="space-y-3">
              <div>
                <label className="text-xs text-gray-400 block mb-1">Entry Price ($)</label>
                <input
                  type="number"
                  step="0.01"
                  value={entryPrice}
                  onChange={(e) => setEntryPrice(e.target.value)}
                  className="w-full bg-gray-800 border border-gray-700 px-3 py-2 rounded font-mono text-sm text-gray-100 focus:outline-none focus:border-emerald-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-gray-400 block mb-1">Stop Type</label>
                  <select
                    value={stopType}
                    onChange={(e) => setStopType(e.target.value)}
                    className="w-full bg-gray-800 border border-gray-700 px-2.5 py-2 rounded font-mono text-xs text-gray-100 focus:outline-none focus:border-emerald-500"
                  >
                    <option value="or-mid">or-mid (OR 50%)</option>
                    <option value="or-low">or-low (OR Low)</option>
                    <option value="pct:1">pct:1 (1% Stop)</option>
                    <option value="pct:2">pct:2 (2% Stop)</option>
                    <option value="atr:1.5">atr:1.5 (1.5x ATR)</option>
                  </select>
                </div>
                <div>
                  <label className="text-xs text-gray-400 block mb-1">Target Type</label>
                  <select
                    value={targetType}
                    onChange={(e) => setTargetType(e.target.value)}
                    className="w-full bg-gray-800 border border-gray-700 px-2.5 py-2 rounded font-mono text-xs text-gray-100 focus:outline-none focus:border-emerald-500"
                  >
                    <option value="2R">2R (2x Risk)</option>
                    <option value="1R">1R (1x Risk)</option>
                    <option value="1.5R">1.5R (1.5x Risk)</option>
                    <option value="3R">3R (3x Risk)</option>
                  </select>
                </div>
              </div>

              <button
                type="submit"
                disabled={planning}
                className="w-full py-2 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white font-semibold text-xs rounded transition-colors"
              >
                {planning ? 'Planning Exit...' : 'Plan Exit'}
              </button>
            </form>

            {planResult && (
              <div className="bg-gray-950 p-3 rounded-lg border border-gray-800 space-y-2 font-mono text-xs">
                <div className="flex justify-between">
                  <span className="text-gray-400">Stop Price:</span>
                  <span className="text-red-400 font-bold">${Number(planResult.stop).toFixed(2)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Target Price:</span>
                  <span className="text-emerald-400 font-bold">${Number(planResult.target).toFixed(2)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Risk (R):</span>
                  <span className="text-gray-200 font-semibold">${Number(planResult.risk).toFixed(2)} / share</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">R:R Ratio:</span>
                  <span className="text-yellow-400 font-bold">{planResult.rr_ratio || '2:1'}</span>
                </div>

                <div className="pt-2">
                  <button
                    onClick={() => {
                      navigate('/timemachine', {
                        state: {
                          symbol: ticker,
                          entry: planResult.entry || entryPrice,
                          stop: planResult.stop,
                          target: planResult.target,
                        },
                      })
                    }}
                    className="w-full py-2 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold rounded text-xs transition-colors flex items-center justify-center gap-1"
                  >
                    <span>Run Time Machine →</span>
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
