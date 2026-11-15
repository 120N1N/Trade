import client from './client'

export const checkRisk = () =>
  client.get('/api/risk/check').then(r => r.data)

export const sizePosition = (plan) =>
  client.post('/api/budget/size', { plan }).then(r => r.data)

export const getConfig = () =>
  client.get('/api/config').then(r => r.data)

export const saveConfig = (config) =>
  client.post('/api/config', config).then(r => r.data)
