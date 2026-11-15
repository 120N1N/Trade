import { useEffect, useRef } from 'react'
import { createChart, CrosshairMode, LineStyle, CandlestickSeries } from 'lightweight-charts'

export default function CandlestickChart({ bars = [], lines = [] }) {
  const containerRef = useRef(null)
  const chartRef = useRef(null)
  const seriesRef = useRef(null)
  const priceLinesRef = useRef([])

  useEffect(() => {
    if (!containerRef.current) return

    const chart = createChart(containerRef.current, {
      layout: {
        background: { color: '#030712' },
        textColor: '#9ca3af',
      },
      grid: {
        vertLines: { color: '#1f2937' },
        horzLines: { color: '#1f2937' },
      },
      crosshair: { mode: CrosshairMode.Normal },
      rightPriceScale: { borderColor: '#374151' },
      timeScale: { borderColor: '#374151', timeVisible: true, secondsVisible: false },
      width: containerRef.current.clientWidth,
      height: containerRef.current.clientHeight || 450,
    })

    const series = chart.addSeries(CandlestickSeries, {
      upColor: '#10b981',
      downColor: '#ef4444',
      borderUpColor: '#10b981',
      borderDownColor: '#ef4444',
      wickUpColor: '#10b981',
      wickDownColor: '#ef4444',
    })

    chartRef.current = chart
    seriesRef.current = series

    const ro = new ResizeObserver(entries => {
      for (const entry of entries) {
        chart.resize(entry.contentRect.width, entry.contentRect.height || 450)
      }
    })
    ro.observe(containerRef.current)

    return () => {
      ro.disconnect()
      chart.remove()
    }
  }, [])

  // Update candle data
  useEffect(() => {
    if (!seriesRef.current || !bars.length) return
    const formatted = bars.map(b => {
      let timeVal = b.time
      if (typeof timeVal === 'string') {
        const d = new Date(timeVal)
        timeVal = isNaN(d.getTime()) ? timeVal : Math.floor(d.getTime() / 1000)
      }
      return {
        time: timeVal,
        open: Number(b.open),
        high: Number(b.high),
        low: Number(b.low),
        close: Number(b.close),
      }
    }).sort((a, b) => (a.time > b.time ? 1 : -1))

    try {
      seriesRef.current.setData(formatted)
      chartRef.current?.timeScale().fitContent()
    } catch (e) {
      console.warn('Error setting chart bars', e)
    }
  }, [bars])

  // Update horizontal price lines
  useEffect(() => {
    if (!seriesRef.current) return

    // Remove existing price lines
    priceLinesRef.current.forEach(pl => {
      try {
        seriesRef.current.removePriceLine(pl)
      } catch (_) {}
    })
    priceLinesRef.current = []

    lines.forEach(({ price, color = '#60a5fa', label = '', lineStyle = LineStyle.Dashed }) => {
      if (price == null || isNaN(Number(price))) return
      try {
        const pl = seriesRef.current.createPriceLine({
          price: Number(price),
          color,
          lineWidth: 2,
          lineStyle,
          axisLabelVisible: true,
          title: label,
        })
        priceLinesRef.current.push(pl)
      } catch (err) {
        console.warn('Error creating price line', err)
      }
    })
  }, [lines])

  return <div ref={containerRef} className="w-full h-full min-h-[450px]" />
}
