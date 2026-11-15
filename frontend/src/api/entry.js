import client from './client'

export const checkEntry = (ticker, setup = 'orb', interval = '5m') =>
  client.get(`/api/entry/${ticker}`, { params: { setup, interval } }).then(r => r.data)

export const getRange = (ticker) =>
  client.get(`/api/entry/${ticker}/range`).then(r => r.data)

export const getBars = (ticker, interval = '5m', period = '1d') =>
  client.get(`/api/bars/${ticker}`, { params: { interval, period } }).then(r => r.data)

export const planExit = (payload) =>
  client.post('/api/exit/plan', payload).then(r => r.data)

export const getPlan = () =>
  client.get('/api/exit/plan').then(r => r.data)
