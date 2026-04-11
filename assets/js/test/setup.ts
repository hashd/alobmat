import { vi } from 'vitest'

// Polyfill localStorage for test environments that don't implement it fully
const localStorageData: Record<string, string> = {}
const localStorageMock = {
  getItem: (key: string) => localStorageData[key] ?? null,
  setItem: (key: string, value: string) => { localStorageData[key] = value },
  removeItem: (key: string) => { delete localStorageData[key] },
  clear: () => { Object.keys(localStorageData).forEach(k => delete localStorageData[k]) },
  get length() { return Object.keys(localStorageData).length },
  key: (i: number) => Object.keys(localStorageData)[i] ?? null,
}

vi.stubGlobal('localStorage', localStorageMock)

// Reset between tests
beforeEach(() => localStorageMock.clear())
