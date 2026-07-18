import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import * as CFI from '../src/epubcfi.js'
import { repairAnnotationTarget } from '../src/annotation-target.js'

const createDocument = () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <p>wrong target</p><p>stable target</p>
  </body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter
  return dom.window.document
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
  return null
}

test('repairs a stale CFI from its saved excerpt', async () => {
  const doc = createDocument()
  const staleRange = doc.createRange()
  staleRange.setStart(doc.body, 0)
  staleRange.collapse(true)
  const target = 'epubcfi(/6/42!/6/1:0)'

  const repaired = await repairAnnotationTarget({
    target,
    excerpt: 'stable target',
    resolveTarget: () => ({ index: 7, anchor: () => staleRange }),
    getDocument: async index => index === 7 ? doc : null,
    findExcerptRange: (document, excerpt) => ({
      range: selectText(document, excerpt),
    }),
    createTarget: (index, range) => `section:${index}:${CFI.fromRange(range)}`,
  })

  assert.notEqual(repaired, target)
  const [, index, cfi] = repaired.match(/^section:(\d+):(.*)$/)
  assert.equal(index, '7')
  assert.equal(CFI.toRange(doc, CFI.parse(cfi)).toString(), 'stable target')
})

test('keeps a valid CFI without invoking text recovery', async () => {
  const doc = createDocument()
  const range = selectText(doc, 'stable target')
  const target = 'epubcfi(/6/42!/4/4/1:0,/1:0,/1:13)'
  let recoveryCalls = 0

  const result = await repairAnnotationTarget({
    target,
    excerpt: 'stable\n target',
    resolveTarget: () => ({ index: 7, anchor: () => range }),
    getDocument: async () => doc,
    findExcerptRange: () => {
      recoveryCalls++
      return null
    },
    createTarget: () => 'unexpected',
  })

  assert.equal(result, target)
  assert.equal(recoveryCalls, 0)
})

test('keeps the original CFI when the excerpt cannot be found', async () => {
  const doc = createDocument()
  const wrongRange = selectText(doc, 'wrong target')
  const target = 'epubcfi(/6/42!/4/2/1:0,/1:0,/1:12)'

  const result = await repairAnnotationTarget({
    target,
    excerpt: 'missing target',
    resolveTarget: () => ({ index: 7, anchor: () => wrongRange }),
    getDocument: async () => doc,
    findExcerptRange: () => null,
    createTarget: () => 'unexpected',
  })

  assert.equal(result, target)
})

test('uses the stale range position to disambiguate repeated excerpts', async () => {
  const doc = createDocument()
  doc.body.innerHTML = `<p>repeated target</p><p>${'padding '.repeat(20)}</p>
    <p>repeated target</p>`
  const occurrences = Array.from(doc.querySelectorAll('p'))
    .filter(element => element.textContent === 'repeated target')
  const staleRange = doc.createRange()
  staleRange.setStart(occurrences[1].firstChild, 0)
  staleRange.collapse(true)
  let preferredOffset

  const result = await repairAnnotationTarget({
    target: 'stale-target',
    excerpt: 'repeated target',
    resolveTarget: () => ({ index: 2, anchor: () => staleRange }),
    getDocument: async () => doc,
    findExcerptRange: (document, excerpt, offset) => {
      preferredOffset = offset
      return { range: selectText(document, excerpt) }
    },
    createTarget: () => 'repaired-target',
  })

  assert.equal(result, 'repaired-target')
  assert.ok(preferredOffset > 100)
})

test('repairs an excerpt containing HTML line breaks and entities', async () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <p>wrong target</p><p id="target">line one<br>line &amp; two</p>
  </body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter
  const doc = dom.window.document
  const staleRange = selectText(doc, 'wrong target')
  const target = doc.getElementById('target')
  const recoveredRange = doc.createRange()
  recoveredRange.setStart(target.firstChild, 0)
  recoveredRange.setEnd(target.lastChild, target.lastChild.length)

  const result = await repairAnnotationTarget({
    target: 'stale-target',
    excerpt: 'line one<BR>line &amp; two',
    resolveTarget: () => ({ index: 3, anchor: () => staleRange }),
    getDocument: async () => doc,
    findExcerptRange: () => ({ range: recoveredRange }),
    createTarget: () => 'repaired-target',
  })

  assert.equal(recoveredRange.toString(), 'line oneline & two')
  assert.equal(result, 'repaired-target')
})
