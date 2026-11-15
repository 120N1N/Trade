import client from './client'

export const runSimulation = (payload) =>
  client.post('/api/timemachine/run', payload).then(r => r.data)
