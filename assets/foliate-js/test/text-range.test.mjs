import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import { createTextRangeFromOffsets } from '../src/text-range.js'

const createDocument = () => {
  const dom = new JSDOM(`<!doctype html><html><body><p>before</p><h1>Chapter</h1></body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter
  return dom.window.document
}

test('a range start at a text-node boundary belongs to the next node', () => {
  const doc = createDocument()
  const start = doc.body.textContent.indexOf('Chapter')
  const range = createTextRangeFromOffsets(doc, start, start + 'Chapter'.length)

  assert.equal(range.toString(), 'Chapter')
  assert.equal(range.startContainer, doc.querySelector('h1').firstChild)
  assert.equal(range.startOffset, 0)
})

test('a collapsed range at a text-node boundary belongs to the next node', () => {
  const doc = createDocument()
  const start = doc.body.textContent.indexOf('Chapter')
  const range = createTextRangeFromOffsets(doc, start)

  assert.equal(range.collapsed, true)
  assert.equal(range.startContainer, doc.querySelector('h1').firstChild)
  assert.equal(range.startOffset, 0)
})
