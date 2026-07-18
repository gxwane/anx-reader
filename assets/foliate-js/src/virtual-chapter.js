import * as CFI from './epubcfi.js'
import { createTextRangeFromOffsets } from './text-range.js'

export const getDocumentBody = doc => {
  if (!doc) return null
  if (doc.body) return doc.body
  if (typeof doc.querySelector === 'function') {
    const body = doc.querySelector('body')
    if (body) return body
  }
  if (typeof doc.getElementsByTagName === 'function') {
    for (const el of Array.from(doc.getElementsByTagName('*'))) {
      if (el.localName?.toLowerCase() === 'body') return el
    }
  }
  return null
}

export const cloneDocument = doc => {
  const cloned = doc.cloneNode(true)
  if (!('body' in cloned)) {
    Object.defineProperty(cloned, 'body', {
      get() { return getDocumentBody(cloned) }
    })
  }
  return cloned
}

export const findVirtualChapterElement = (doc, id) => {
  const body = getDocumentBody(doc)
  if (!body || !id) return null
  return body.querySelector(`#${CSS.escape(id)}`)
    ?? body.querySelector(`[name="${CSS.escape(id)}"]`)
}

const INDEX_MARKER_PREFIX = 'index_'
const LEGACY_BODY_ID_PREFIX = 'vcs_'

export const getLegacyVirtualChapterMarker = value => {
  if (typeof value !== 'string' || !value.includes(`[${LEGACY_BODY_ID_PREFIX}`)) {
    return null
  }

  try {
    const parsed = CFI.parse(value)
    const paths = parsed?.parent ?? parsed
    // Historical virtual-chapter CFIs put vcs_ on the document body's CFI
    // step: the first step of the final indirection path. IDs on package or
    // descendant elements are ordinary EPUB IDs and must not be classified.
    const id = paths?.at(-1)?.[0]?.id
    if (id?.startsWith(LEGACY_BODY_ID_PREFIX)) {
      return id.slice(LEGACY_BODY_ID_PREFIX.length) || null
    }
  } catch {
    // Invalid CFIs are handled by the normal navigation failure path.
  }
  return null
}

export const getVirtualChapterMarker = (vChapter, chapterIndex = 0) =>
  vChapter?.fragmentStart ?? `${INDEX_MARKER_PREFIX}${Math.max(0, chapterIndex ?? 0)}`

export const getVirtualChapterBodyId = (vChapter, chapterIndex = 0) =>
  `vcs_${getVirtualChapterMarker(vChapter, chapterIndex)}`

export const resolveVirtualChapterFromMarker = (virtualChapters, marker) => {
  if (!Array.isArray(virtualChapters) || !marker) return null

  const exactIndex = virtualChapters.findIndex(vc => vc?.fragmentStart === marker)
  if (exactIndex >= 0) return exactIndex

  if (marker.startsWith(INDEX_MARKER_PREFIX)) {
    const index = Number(marker.slice(INDEX_MARKER_PREFIX.length))
    return Number.isInteger(index) && index >= 0 && index < virtualChapters.length
      ? index
      : null
  }

  return null
}

const selectVirtualChapterEntries = entries => {
  if (!Array.isArray(entries) || entries.length <= 1) return null

  const byDepth = new Map()
  for (const entry of entries) {
    if (!byDepth.has(entry.depth)) byDepth.set(entry.depth, [])
    byDepth.get(entry.depth).push(entry)
  }

  let selected = null
  for (const depth of [...byDepth.keys()].sort((a, b) => a - b)) {
    const candidates = byDepth.get(depth)
    if (candidates.length > 1) {
      selected = candidates
      break
    }
  }
  if (!selected) return null

  const seen = new Set()
  const unique = []
  for (const entry of selected) {
    const key = entry.fragment ?? '__root__'
    if (seen.has(key)) continue
    seen.add(key)
    unique.push(entry)
  }
  if (unique.length <= 1 || !unique.some(entry => entry.fragment != null)) return null

  return unique
}

const toVirtualChapterPlan = entries => entries.map((entry, index) => ({
  fragmentStart: entry.fragment,
  fragmentEnd: entries[index + 1]?.fragment ?? null,
  tocItem: entry.tocItem,
}))

// Input-boundary compatibility only: reproduces the partition used by older
// releases when they generated destructive-slice vcs_ CFIs.
export const buildLegacyVirtualChapterPlan = entries => {
  const selected = selectVirtualChapterEntries(entries)
  return selected ? toVirtualChapterPlan(selected) : null
}

export const buildVirtualChapterPlan = entries => {
  const selected = selectVirtualChapterEntries(entries)
  if (!selected) return null
  const unique = [...selected]

  if (unique[0].fragment != null) {
    const firstIndex = entries.indexOf(unique[0])
    const root = entries
      .slice(0, Math.max(0, firstIndex))
      .filter(entry => entry.fragment == null && entry.depth < unique[0].depth)
      .at(-1)
    if (root) unique.unshift(root)
    else unique[0] = { ...unique[0], fragment: null }
  }
  if (unique[0].fragment != null) return null

  return toVirtualChapterPlan(unique)
}

export const validateVirtualChapterPartition = (doc, virtualChapters) => {
  if (!Array.isArray(virtualChapters) || virtualChapters.length === 0) return false
  if (virtualChapters[0]?.fragmentStart != null) return false
  if (virtualChapters.at(-1)?.fragmentEnd != null) return false

  const boundaries = []
  for (let index = 0; index < virtualChapters.length; index++) {
    const current = virtualChapters[index]
    const next = virtualChapters[index + 1]
    if (next && current.fragmentEnd !== next.fragmentStart) return false
    if (current.fragmentStart == null) continue
    const element = findVirtualChapterElement(doc, current.fragmentStart)
    if (!element) return false
    boundaries.push(element)
  }

  for (let index = 1; index < boundaries.length; index++) {
    const position = boundaries[index - 1].compareDocumentPosition(boundaries[index])
    if (!(position & Node.DOCUMENT_POSITION_FOLLOWING)) return false
  }
  return true
}

// Compute virtual chapter text-length metrics on the full document.
// This maps chapter-local progress and offsets back to section-local values.
export const computeVirtualChapterTextMetrics = (doc, virtualChapters) => {
  const body = getDocumentBody(doc)
  if (!body || !Array.isArray(virtualChapters) || virtualChapters.length === 0) return null

  const idToEl = new Map()
  for (const vc of virtualChapters) {
    if (vc?.fragmentStart) idToEl.set(vc.fragmentStart, findVirtualChapterElement(doc, vc.fragmentStart))
    if (vc?.fragmentEnd) idToEl.set(vc.fragmentEnd, findVirtualChapterElement(doc, vc.fragmentEnd))
  }

  for (const vc of virtualChapters) {
    if (vc?.fragmentStart && !idToEl.get(vc.fragmentStart)) return null
  }

  const boundaryEls = new Set(Array.from(idToEl.values()).filter(Boolean))
  const elToPos = new Map()
  let pos = 0
  const it = doc.createNodeIterator(body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)
  for (let node = it.nextNode(); node; node = it.nextNode()) {
    if (node.nodeType === 1) {
      if (boundaryEls.has(node) && !elToPos.has(node)) elToPos.set(node, pos)
    } else if (node.nodeType === 3) {
      pos += node.nodeValue?.length ?? 0
    }
  }

  const idToPos = new Map()
  for (const [id, el] of idToEl.entries()) {
    if (id && el) idToPos.set(id, elToPos.get(el) ?? 0)
  }

  const lens = []
  const cum = []
  let sum = 0
  for (let i = 0; i < virtualChapters.length; i++) {
    cum[i] = sum
    const vc = virtualChapters[i]
    const start = vc?.fragmentStart ? (idToPos.get(vc.fragmentStart) ?? 0) : 0
    const end = vc?.fragmentEnd ? (idToPos.get(vc.fragmentEnd) ?? pos) : pos
    const len = Math.max(0, end - start)
    lens[i] = len
    sum += len
  }

  if (!Number.isFinite(sum) || sum <= 0) return null
  return { lens, cum, total: sum }
}

export const mapVChapterFractionToSectionFraction = (metrics, chapterIndex, localFraction) => {
  if (!metrics || !Number.isFinite(metrics.total) || metrics.total <= 0) return null
  const i = Math.max(0, Math.min(chapterIndex ?? 0, (metrics.lens?.length ?? 1) - 1))
  const before = metrics.cum?.[i] ?? 0
  const len = metrics.lens?.[i] ?? 0
  const f = Math.max(0, Math.min(1, localFraction ?? 0))
  if (len <= 0) return before / metrics.total
  return (before + f * len) / metrics.total
}

export const mapSectionFractionToVChapter = (metrics, sectionFraction) => {
  if (!metrics || !Number.isFinite(metrics.total) || metrics.total <= 0) return null
  const f = Math.max(0, Math.min(1, sectionFraction ?? 0))
  const target = f * metrics.total
  const lens = metrics.lens ?? []
  const cum = metrics.cum ?? []
  for (let i = 0; i < lens.length; i++) {
    const start = cum[i] ?? 0
    const len = lens[i] ?? 0
    if (len <= 0) continue
    if (target < start + len || i === lens.length - 1) {
      const local = (target - start) / len
      return { chapterIndex: i, localAnchor: Math.max(0, Math.min(1, local)) }
    }
  }
  return { chapterIndex: 0, localAnchor: 0 }
}

const VIRTUAL_CHAPTER_HIDDEN_ATTRIBUTE = 'data-foliate-vchapter-hidden'

const getRangeBoundaryNode = (container, offset, usePrevious) => {
  if (container?.nodeType !== 1 || !container.childNodes?.length) return container
  const index = usePrevious
    ? Math.max(0, Math.min(container.childNodes.length - 1, offset - 1))
    : Math.max(0, Math.min(container.childNodes.length - 1, offset))
  return container.childNodes[index]
}

const isNodeInHiddenVirtualChapter = node => {
  const element = node?.nodeType === 1 ? node : node?.parentElement
  return element?.closest?.(`[${VIRTUAL_CHAPTER_HIDDEN_ATTRIBUTE}]`) != null
}

export const isRangeInHiddenVirtualChapter = range => {
  if (!range?.startContainer) return false
  const start = getRangeBoundaryNode(
    range.startContainer, range.startOffset ?? 0, false)
  if (isNodeInHiddenVirtualChapter(start)) return true
  if (range.collapsed || !range.endContainer) return false
  const end = getRangeBoundaryNode(
    range.endContainer, range.endOffset ?? 0, true)
  return isNodeInHiddenVirtualChapter(end)
}

export const isolateVirtualChapter = (doc, vChapter) => {
  const { fragmentStart, fragmentEnd } = vChapter
  const body = getDocumentBody(doc)
  if (!body || (!fragmentStart && !fragmentEnd)) return

  const startEl = fragmentStart ? findVirtualChapterElement(doc, fragmentStart) : null
  const endEl = fragmentEnd ? findVirtualChapterElement(doc, fragmentEnd) : null

  if (fragmentStart && !startEl) {
    console.warn(`[VirtualChapter] Start fragment not found: ${fragmentStart}`)
    return
  }

  const hide = element => {
    if (element?.nodeType === 1) {
      element.setAttribute(VIRTUAL_CHAPTER_HIDDEN_ATTRIBUTE, '')
      element.style.setProperty('display', 'none', 'important')
    }
  }
  const affectsLayout = node => node?.nodeType === 1
    || (node?.nodeType === 3 && Boolean(node.nodeValue?.trim()))

  try {
    if (startEl) {
      let node = startEl
      while (node && node !== body) {
        for (let sibling = node.previousSibling; sibling; sibling = sibling.previousSibling) {
          hide(sibling)
        }
        node = node.parentNode
      }
    }

    if (endEl) {
      let node = endEl
      let canHideWholeNode = true
      while (node && node !== body) {
        if (canHideWholeNode) hide(node)
        for (let sibling = node.nextSibling; sibling; sibling = sibling.nextSibling) {
          hide(sibling)
        }
        if (canHideWholeNode) {
          for (let sibling = node.previousSibling; sibling; sibling = sibling.previousSibling) {
            if (affectsLayout(sibling)) {
              canHideWholeNode = false
              break
            }
          }
        }
        node = node.parentNode
      }
    }
  } catch (e) {
    console.warn('[VirtualChapter] DOM isolate failed:', e)
  }
}

export const applyLegacyVirtualChapterSlice = (doc, vChapter, chapterIndex = 0) => {
  const { fragmentStart, fragmentEnd } = vChapter
  const body = getDocumentBody(doc)
  if (!body || (!fragmentStart && !fragmentEnd)) return

  const startEl = fragmentStart ? findVirtualChapterElement(doc, fragmentStart) : null
  const endEl = fragmentEnd ? findVirtualChapterElement(doc, fragmentEnd) : null
  if (fragmentStart && !startEl) return

  const range = doc.createRange()
  if (startEl) range.setStartBefore(startEl)
  else range.setStart(body, 0)
  if (endEl) range.setEndBefore(endEl)
  else range.setEnd(body, body.childNodes.length)

  const fragment = range.extractContents()
  body.replaceChildren(fragment)
  body.id = getVirtualChapterBodyId(vChapter, chapterIndex)
}

const getRangeTextOffsets = (doc, range) => {
  const body = getDocumentBody(doc)
  if (!body || !range?.startContainer) return null

  const prefix = doc.createRange()
  prefix.selectNodeContents(body)
  prefix.setEnd(range.startContainer, range.startOffset)
  const start = prefix.toString().length
  prefix.setEnd(range.endContainer, range.endOffset)
  return { start, end: prefix.toString().length }
}

export const mapLegacyRangeToFullDocument = (doc, legacyDoc, legacyRange, vChapter) => {
  const body = getDocumentBody(doc)
  if (!body) return null

  const localOffsets = getRangeTextOffsets(legacyDoc, legacyRange)
  if (!localOffsets) return null

  const startEl = vChapter.fragmentStart
    ? findVirtualChapterElement(doc, vChapter.fragmentStart)
    : null
  const endEl = vChapter.fragmentEnd
    ? findVirtualChapterElement(doc, vChapter.fragmentEnd)
    : null
  if (vChapter.fragmentStart && !startEl) return null
  // The historical slicer treated an unresolved end fragment as the body end.
  // Reproduce that only for legacy input conversion.

  const getOffsetBefore = element => {
    const prefix = doc.createRange()
    prefix.selectNodeContents(body)
    prefix.setEndBefore(element)
    return prefix.toString().length
  }
  const chapterStart = startEl ? getOffsetBefore(startEl) : 0
  const chapterEnd = endEl ? getOffsetBefore(endEl) : body.textContent.length
  const chapterLength = Math.max(0, chapterEnd - chapterStart)
  const start = chapterStart + Math.min(localOffsets.start, chapterLength)
  const end = chapterStart + Math.min(localOffsets.end, chapterLength)
  return createTextRangeFromOffsets(doc, start, end)
}

export const normalizeLegacyVirtualChapterTarget = async ({
  target,
  resolveCFI,
  sections,
  getDocument,
  createTarget,
}) => {
  const marker = getLegacyVirtualChapterMarker(target)
  if (!marker) return target

  let resolved
  try {
    resolved = resolveCFI?.(target)
  } catch {
    return null
  }
  const index = resolved?.index
  if (!Number.isInteger(index) || index < 0 || typeof resolved?.anchor !== 'function') {
    return null
  }

  let doc
  try {
    doc = await getDocument(index)
  } catch {
    return null
  }
  if (!doc) return null

  // A publisher may legitimately use a vcs_ body ID. If the CFI resolves on
  // the intact document, it is already standard and must remain untouched.
  try {
    if (resolved.anchor(doc)) return target
  } catch {
    // Historical sliced CFIs normally fail here because the synthetic body ID
    // does not exist in the intact document. Convert those at this boundary.
  }

  const section = sections?.[index]
  const legacyVirtualChapters = section?.legacyVirtualChapters
    ?? section?.virtualChapters
  const chapterIndex = resolveVirtualChapterFromMarker(
    legacyVirtualChapters, marker)
  if (chapterIndex == null) return target

  try {
    const legacyDoc = cloneDocument(doc)
    applyLegacyVirtualChapterSlice(
      legacyDoc, legacyVirtualChapters[chapterIndex], chapterIndex)
    const legacyRange = resolved.anchor(legacyDoc)
    const range = mapLegacyRangeToFullDocument(
      doc, legacyDoc, legacyRange, legacyVirtualChapters[chapterIndex])
    return range ? createTarget(index, range) : null
  } catch {
    return null
  }
}

export const resolveVirtualChapterFromAnchor = (virtualChapters, anchor, doc) => {
  if (!Array.isArray(virtualChapters) || virtualChapters.length === 0 || !anchor) return 0

  if (typeof anchor === 'function' && doc) {
    const result = anchor(doc)
    if (result?.startContainer || result?.nodeType === 1) {
      const target = result?.startContainer ? result.startContainer : result
      for (let i = virtualChapters.length - 1; i >= 0; i--) {
        const vc = virtualChapters[i]
        if (!vc.fragmentStart) continue
        const startEl = findVirtualChapterElement(doc, vc.fragmentStart)
        if (!startEl) continue
        const position = startEl.compareDocumentPosition(target)
        if (position === 0 || position & Node.DOCUMENT_POSITION_FOLLOWING) return i
      }
    }
    return 0
  }

  if (typeof anchor === 'number') {
    return Math.min(Math.floor(anchor * virtualChapters.length), virtualChapters.length - 1)
  }

  return 0
}
