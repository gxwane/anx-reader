import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import * as CFI from '../src/epubcfi.js'
import {
  applyLegacyVirtualChapterSlice,
  buildLegacyVirtualChapterPlan,
  buildVirtualChapterPlan,
  cloneDocument,
  getLegacyVirtualChapterMarker,
  isRangeInHiddenVirtualChapter,
  isolateVirtualChapter,
  mapLegacyRangeToFullDocument,
  normalizeLegacyVirtualChapterTarget,
  resolveVirtualChapterFromAnchor,
  resolveVirtualChapterFromMarker,
  validateVirtualChapterPartition,
} from '../src/virtual-chapter.js'

const virtualChapters = [
  { fragmentStart: null, fragmentEnd: 'chapter-2' },
  { fragmentStart: 'chapter-2', fragmentEnd: 'chapter-3' },
  { fragmentStart: 'chapter-3', fragmentEnd: null },
]

const createDocument = () => {
  const dom = new JSDOM(`<!doctype html><html><body id="book-body">
    <section><h1 id="chapter-1">One</h1><p>alpha target one</p></section>
    <section><h1 id="chapter-2">Two</h1><p>beta target two</p></section>
    <section><h1 id="chapter-3">Three</h1><p>gamma target three</p></section>
  </body></html>`)
  const { window } = dom
  globalThis.Node = window.Node
  globalThis.NodeFilter = window.NodeFilter
  globalThis.CSS = window.CSS ?? { escape: value => value }
  if (!globalThis.CSS.escape) globalThis.CSS.escape = value => value
  return window.document
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

test('standard CFI survives non-destructive virtual chapter isolation', () => {
  const doc = createDocument()
  const range = selectText(doc, 'target two')
  const cfi = CFI.fromRange(range)
  const children = Array.from(doc.body.childNodes)

  assert.equal(
    resolveVirtualChapterFromAnchor(virtualChapters, () => range, doc),
    1,
  )
  isolateVirtualChapter(doc, virtualChapters[1])

  assert.deepEqual(Array.from(doc.body.childNodes), children)
  assert.equal(doc.body.id, 'book-body')
  assert.equal(CFI.toRange(doc, CFI.parse(cfi)).toString(), 'target two')
  assert.equal(doc.getElementById('chapter-2').closest('section').style.display, '')
  assert.equal(doc.getElementById('chapter-1').closest('section').style.display, 'none')
  assert.equal(doc.getElementById('chapter-3').closest('section').style.display, 'none')
})

test('legacy sliced CFI maps to a standard full-document CFI', () => {
  const doc = createDocument()
  const legacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(legacyDoc, virtualChapters[1], 1)
  const legacyRange = selectText(legacyDoc, 'target two')
  const legacyCfi = CFI.fromRange(legacyRange)

  const recreatedLegacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(recreatedLegacyDoc, virtualChapters[1], 1)
  const recreatedLegacyRange = CFI.toRange(recreatedLegacyDoc, CFI.parse(legacyCfi))
  const fullRange = mapLegacyRangeToFullDocument(
    doc,
    recreatedLegacyDoc,
    recreatedLegacyRange,
    virtualChapters[1],
  )
  const standardCfi = CFI.fromRange(fullRange)

  assert.match(legacyCfi, /vcs_chapter-2/)
  assert.doesNotMatch(standardCfi, /vcs_/)
  isolateVirtualChapter(doc, virtualChapters[1])
  assert.equal(CFI.toRange(doc, CFI.parse(standardCfi)).toString(), 'target two')
})

test('legacy first virtual chapter marker maps without a fragment start', () => {
  const doc = createDocument()
  const legacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(legacyDoc, virtualChapters[0], 0)
  const legacyRange = selectText(legacyDoc, 'target one')
  const legacyCfi = CFI.fromRange(legacyRange)
  const fullRange = mapLegacyRangeToFullDocument(
    doc,
    legacyDoc,
    legacyRange,
    virtualChapters[0],
  )

  assert.match(legacyCfi, /vcs_index_0/)
  assert.equal(fullRange.toString(), 'target one')
  assert.equal(resolveVirtualChapterFromAnchor(virtualChapters, () => fullRange, doc), 0)
})

test('legacy mapping treats a missing end fragment as the document end', () => {
  const doc = createDocument()
  const legacyChapter = {
    fragmentStart: 'chapter-2',
    fragmentEnd: 'missing-end',
  }
  const legacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(legacyDoc, legacyChapter, 1)
  const legacyRange = selectText(legacyDoc, 'target three')
  const fullRange = mapLegacyRangeToFullDocument(
    doc, legacyDoc, legacyRange, legacyChapter)

  assert.equal(fullRange?.toString(), 'target three')
})

test('legacy mapping biases a chapter-start range into the new chapter', () => {
  const doc = createDocument()
  const legacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(legacyDoc, virtualChapters[1], 1)
  const legacyRange = selectText(legacyDoc, 'Two')
  const fullRange = mapLegacyRangeToFullDocument(
    doc, legacyDoc, legacyRange, virtualChapters[1])

  assert.equal(fullRange.toString(), 'Two')
  assert.equal(fullRange.startContainer, doc.getElementById('chapter-2').firstChild)
  assert.equal(
    resolveVirtualChapterFromAnchor(virtualChapters, () => fullRange, doc),
    1,
  )
})

test('virtual chapter plan preserves content before the first child fragment', () => {
  const root = { label: 'Root chapter' }
  const childOne = { label: 'Child one' }
  const childTwo = { label: 'Child two' }
  const entries = [
    { fragment: null, tocItem: root, depth: 0 },
    { fragment: 'chapter-2', tocItem: childOne, depth: 1 },
    { fragment: 'chapter-3', tocItem: childTwo, depth: 1 },
  ]

  assert.deepEqual(buildVirtualChapterPlan(entries), [
    { fragmentStart: null, fragmentEnd: 'chapter-2', tocItem: root },
    { fragmentStart: 'chapter-2', fragmentEnd: 'chapter-3', tocItem: childOne },
    { fragmentStart: 'chapter-3', fragmentEnd: null, tocItem: childTwo },
  ])
})

test('virtual chapter plan absorbs a fragment-only prefix into the first chapter', () => {
  const childOne = { label: 'Child one' }
  const childTwo = { label: 'Child two' }
  const entries = [
    { fragment: 'chapter-2', tocItem: childOne, depth: 1 },
    { fragment: 'chapter-3', tocItem: childTwo, depth: 1 },
  ]

  assert.deepEqual(buildVirtualChapterPlan(entries), [
    { fragmentStart: null, fragmentEnd: 'chapter-3', tocItem: childOne },
    { fragmentStart: 'chapter-3', fragmentEnd: null, tocItem: childTwo },
  ])
})

test('legacy plan retains fragment-only slicing for old CFI conversion', () => {
  const childOne = { label: 'Child one' }
  const childTwo = { label: 'Child two' }
  const entries = [
    { fragment: 'chapter-2', tocItem: childOne, depth: 1 },
    { fragment: 'chapter-3', tocItem: childTwo, depth: 1 },
  ]

  const legacyPlan = buildLegacyVirtualChapterPlan(entries)
  assert.deepEqual(legacyPlan, [
    { fragmentStart: 'chapter-2', fragmentEnd: 'chapter-3', tocItem: childOne },
    { fragmentStart: 'chapter-3', fragmentEnd: null, tocItem: childTwo },
  ])

  const doc = createDocument()
  const legacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(legacyDoc, legacyPlan[0], 0)
  const legacyRange = selectText(legacyDoc, 'target two')
  const legacyCfi = CFI.fromRange(legacyRange)
  const resolvedLegacyRange = CFI.toRange(legacyDoc, CFI.parse(legacyCfi))
  const fullRange = mapLegacyRangeToFullDocument(
    doc, legacyDoc, resolvedLegacyRange, legacyPlan[0])

  assert.match(legacyCfi, /vcs_chapter-2/)
  assert.equal(fullRange.toString(), 'target two')
})

test('legacy marker extraction honors EPUB CFI escaping', () => {
  const doc = createDocument()
  doc.body.id = 'vcs_part;2^x]'
  const cfi = CFI.fromRange(selectText(doc, 'target two'))

  assert.match(cfi, /vcs_part\^;2\^\^x\^\]/)
  assert.equal(
    getLegacyVirtualChapterMarker(cfi),
    'part;2^x]',
  )
})

test('legacy marker extraction ignores vcs_ ids below the document body', () => {
  const doc = createDocument()
  const target = doc.querySelector('p')
  target.id = 'vcs_real'
  const cfi = CFI.fromRange(selectText(doc, 'target one'))

  assert.match(cfi, /vcs_real/)
  assert.equal(getLegacyVirtualChapterMarker(cfi), null)
})

test('legacy marker extraction ignores vcs_ ids in package paths', () => {
  const cfi = 'epubcfi(/6[vcs_package]/2!/4/2,/1:0,/1:4)'

  assert.equal(getLegacyVirtualChapterMarker(cfi), null)
})

test('a resolvable standard CFI with a vcs_ body id is not converted', async () => {
  const doc = createDocument()
  doc.body.id = 'vcs_chapter-2'
  const target = CFI.fromRange(selectText(doc, 'target two'))
  const result = await normalizeLegacyVirtualChapterTarget({
    target,
    resolveCFI: value => ({
      index: 0,
      anchor: document => CFI.toRange(document, CFI.parse(value)),
    }),
    sections: [{
      legacyVirtualChapters: [
        { fragmentStart: 'chapter-2', fragmentEnd: null },
      ],
    }],
    getDocument: async () => doc,
    createTarget: () => {
      throw new Error('standard target must not be converted')
    },
  })

  assert.equal(getLegacyVirtualChapterMarker(target), 'chapter-2')
  assert.equal(result, target)
})

test('legacy target normalization converts only after full-document resolution fails', async () => {
  const doc = createDocument()
  const legacyDoc = cloneDocument(doc)
  applyLegacyVirtualChapterSlice(legacyDoc, virtualChapters[1], 1)
  const target = CFI.fromRange(selectText(legacyDoc, 'target two'))

  const result = await normalizeLegacyVirtualChapterTarget({
    target,
    resolveCFI: value => ({
      index: 0,
      anchor: document => CFI.toRange(document, CFI.parse(value)),
    }),
    sections: [{ legacyVirtualChapters: virtualChapters }],
    getDocument: async () => doc,
    createTarget: (index, range) => {
      assert.equal(index, 0)
      return CFI.fromRange(range)
    },
  })

  assert.match(target, /vcs_chapter-2/)
  assert.doesNotMatch(result, /vcs_/)
  assert.equal(CFI.toRange(doc, CFI.parse(result)).toString(), 'target two')
})

test('a real index_ fragment wins over the synthetic marker fallback', () => {
  const chapters = [
    { fragmentStart: null, fragmentEnd: 'index_0' },
    { fragmentStart: 'index_0', fragmentEnd: null },
  ]

  assert.equal(resolveVirtualChapterFromMarker(chapters, 'index_0'), 1)
})

test('virtual chapter partition validation rejects gaps and missing boundaries', () => {
  const doc = createDocument()
  assert.equal(validateVirtualChapterPartition(doc, virtualChapters), true)
  assert.equal(validateVirtualChapterPartition(doc, [
    { fragmentStart: null, fragmentEnd: 'chapter-2' },
    { fragmentStart: 'chapter-3', fragmentEnd: null },
  ]), false)
  assert.equal(validateVirtualChapterPartition(doc, [
    { fragmentStart: null, fragmentEnd: 'missing' },
    { fragmentStart: 'missing', fragmentEnd: null },
  ]), false)
})

test('annotation ranges in isolated virtual chapters are marked as hidden', () => {
  const doc = createDocument()
  const before = selectText(doc, 'target one')
  const visible = selectText(doc, 'target two')
  const after = selectText(doc, 'target three')

  isolateVirtualChapter(doc, virtualChapters[1])

  assert.equal(isRangeInHiddenVirtualChapter(before), true)
  assert.equal(isRangeInHiddenVirtualChapter(visible), false)
  assert.equal(isRangeInHiddenVirtualChapter(after), true)
})

test('publisher-hidden content is not mistaken for an isolated virtual chapter', () => {
  const doc = createDocument()
  const range = selectText(doc, 'target two')
  range.startContainer.parentElement.style.display = 'none'

  assert.equal(isRangeInHiddenVirtualChapter(range), false)
})
