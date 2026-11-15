const STATUS = {
  WAITING: {
    label: 'WAITING',
    emoji: '🟡',
    cls: 'bg-yellow-900 border-yellow-600 text-yellow-400',
  },
  TRIGGERED: {
    label: 'TRIGGERED',
    emoji: '🟢',
    cls: 'bg-emerald-900 border-emerald-600 text-emerald-400',
  },
  EXPIRED: {
    label: 'EXPIRED',
    emoji: '🔴',
    cls: 'bg-red-900 border-red-700 text-red-400',
  },
}

export default function StatusBadge({ status = 'WAITING' }) {
  const s = STATUS[status] ?? STATUS.WAITING
  return (
    <span className={`inline-flex items-center gap-2 px-4 py-2 rounded-full border text-sm font-semibold tracking-wide ${s.cls}`}>
      <span>{s.emoji}</span>
      <span>{s.label}</span>
    </span>
  )
}
