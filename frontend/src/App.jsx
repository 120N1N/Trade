import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import Layout from './components/Layout'
import Scanner from './pages/Scanner'
import EntryExit from './pages/EntryExit'
import TimeMachine from './pages/TimeMachine'
import RiskBudget from './pages/RiskBudget'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Navigate to="/scanner" replace />} />
          <Route path="scanner" element={<Scanner />} />
          <Route path="entry" element={<EntryExit />} />
          <Route path="entry/:ticker" element={<EntryExit />} />
          <Route path="timemachine" element={<TimeMachine />} />
          <Route path="risk" element={<RiskBudget />} />
          <Route path="*" element={<Navigate to="/scanner" replace />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
