import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import * as CFI from '../src/epubcfi.js'
import {
  HTML_MEDIA_TYPE,
  XHTML_MEDIA_TYPE,
  parseContentDocument,
  serializeContentDocument,
} from '../src/content-document.js'

const createDOMEnvironment = () => {
  const dom = new JSDOM('<!doctype html><html><body></body></html>')
  globalThis.Node = dom.window.Node
  globalThis.NodeFilter = dom.window.NodeFilter
  globalThis.DOMParser = dom.window.DOMParser
  globalThis.XMLSerializer = dom.window.XMLSerializer
  return dom.window
}

const selectText = (doc, query) => {
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
  while (walker.nextNode()) {
    const node = walker.currentNode
    const start = node.nodeValue.indexOf(query)
    if (start < 0) continue
    const range = doc.createRange()
    range.setStart(node, start)
    range.setEnd(node, start + query.length)
    return range
  }
  throw new Error(`Text not found: ${query}`)
}

test('invalid XHTML is canonicalized to the same HTML DOM used for display', () => {
  const window = createDOMEnvironment()
  const source = `<?xml version="1.0"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>Broken XHTML</title></head>
      <body><p>alpha</p><br><p>stable target</p></body>
    </html>`

  const parsed = parseContentDocument(source, XHTML_MEDIA_TYPE)
  assert.equal(parsed.mediaType, HTML_MEDIA_TYPE)
  assert.equal(parsed.recoveredFromInvalidXHTML, true)
  assert.equal(parsed.document.querySelector('parsererror'), null)

  const range = selectText(parsed.document, 'stable target')
  const cfi = CFI.fromRange(range)
  const serialized = serializeContentDocument(parsed.document)
  const displayed = new window.DOMParser().parseFromString(serialized, parsed.mediaType)

  assert.equal(CFI.toRange(displayed, CFI.parse(cfi)).toString(), 'stable target')
})

test('valid XHTML retains its declared media type', () => {
  createDOMEnvironment()
  const source = `<html xmlns="http://www.w3.org/1999/xhtml">
    <head><title>Valid XHTML</title></head>
    <body><p>target</p><br /><p>after</p></body>
  </html>`

  const parsed = parseContentDocument(source, XHTML_MEDIA_TYPE)

  assert.equal(parsed.mediaType, XHTML_MEDIA_TYPE)
  assert.equal(parsed.recoveredFromInvalidXHTML, false)
  assert.equal(parsed.document.body.textContent.trim(), 'targetafter')
})
