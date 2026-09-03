import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import * as CFI from '../src/epubcfi.js'
import {
  repairAnnotationTarget,
  buildRangeFingerprint,
  calculateContextScore,
} from '../src/annotation-target.js'

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

test('buildRangeFingerprint extracts prefix and suffix within block-level container', () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <p>This is the leading context text before the thesis statement and this is the trailing text.</p>
  </body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter
  const doc = dom.window.document
  const range = selectText(doc, 'thesis statement')
  assert.ok(range)

  const { prefix, suffix } = buildRangeFingerprint(range, 20)
  assert.ok(prefix.endsWith('before the'))
  assert.ok(suffix.startsWith('and this'))
})

test('calculateContextScore handles asymmetric boundary conditions and short context', () => {
  // Case 1: Chapter start (empty prefix)
  const scoreAtStart = calculateContextScore('', 'next words', '', 'next words')
  assert.equal(scoreAtStart, 1.0)

  // Case 2: Chapter end (empty suffix)
  const scoreAtEnd = calculateContextScore('prev words', '', 'prev words', '')
  assert.equal(scoreAtEnd, 1.0)

  // Case 3: Middle match
  const scoreMiddle = calculateContextScore('before text', 'after text', 'before text', 'after text')
  assert.equal(scoreMiddle, 1.0)

  // Case 4: Complete mismatch
  const scoreMismatch = calculateContextScore('completely wrong', 'unrelated text', 'before text', 'after text')
  assert.ok(scoreMismatch < 0.3)
})

test('repairs repeated short phrases by picking the correct candidate based on context fingerprint (not 1st match)', async () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <p>Section 1: The target is here.</p>
    <p>Section 2: Another target is here.</p>
    <p>Section 3: Yet another target is here.</p>
    <p>Section 4: The special target was chosen.</p>
    <p>Section 5: Final target is here.</p>
  </body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter
  const doc = dom.window.document

  // 5 target occurrences
  const candidates = []
  const ps = Array.from(doc.querySelectorAll('p'))
  for (const p of ps) {
    const textNode = p.firstChild
    const start = textNode.nodeValue.indexOf('target')
    if (start >= 0) {
      const range = doc.createRange()
      range.setStart(textNode, start)
      range.setEnd(textNode, start + 6)
      candidates.push({ range, offset: start })
    }
  }
  assert.equal(candidates.length, 5)

  // Invalid stale range
  const staleRange = doc.createRange()
  staleRange.setStart(doc.body, 0)
  staleRange.collapse(true)

  // We want candidate index 3 ("Section 4: The special target was chosen.")
  const expectedPrefix = 'The special '
  const expectedSuffix = ' was chosen.'

  let chosenTarget = null
  const result = await repairAnnotationTarget({
    target: 'stale-cfi',
    excerpt: 'target',
    prefix: expectedPrefix,
    suffix: expectedSuffix,
    resolveTarget: () => ({ index: 0, anchor: () => staleRange }),
    getDocument: async () => doc,
    findAllExcerptRanges: () => candidates,
    createTarget: (index, range) => {
      chosenTarget = range.startContainer.parentElement.textContent
      return 'repaired-fourth-target'
    },
  })

  assert.equal(result, 'repaired-fourth-target')
  assert.ok(chosenTarget.includes('Section 4: The special target was chosen.'))
})

test('gracefully degrades when similarity score is below 0.7 threshold', async () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <p>Different text entirely without target.</p>
  </body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter
  const doc = dom.window.document

  const staleRange = doc.createRange()
  staleRange.setStart(doc.body, 0)
  staleRange.collapse(true)

  const originalTarget = 'original-cfi-coordinate'
  const result = await repairAnnotationTarget({
    target: originalTarget,
    excerpt: 'missing content',
    prefix: 'unrelated',
    suffix: 'unrelated',
    resolveTarget: () => ({ index: 0, anchor: () => staleRange }),
    getDocument: async () => doc,
    findAllExcerptRanges: () => [],
    createTarget: () => 'should-not-be-called',
  })

  assert.equal(result, originalTarget)
})

