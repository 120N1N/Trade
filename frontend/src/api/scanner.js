import client from './client'

export const scanORB = (at = '10:15', limit = 50) =>
  client.get('/api/scan/orb', { params: { at, limit } }).then(r => r.data)

export const scanDaily = (limit = 100) =>
  client.get('/api/scan/daily', { params: { limit } }).then(r => r.data)

export const scanStatus = () =>
  client.get('/api/scan/status').then(r => r.data)
