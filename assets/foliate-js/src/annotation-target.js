import { getOpenCCConverter } from './chinese-converter.js'

const decodeExcerptEntities = value => value
  .replace(/&nbsp;/gi, ' ')
  .replace(/&amp;/gi, '&')
  .replace(/&lt;/gi, '<')
  .replace(/&gt;/gi, '>')
  .replace(/&quot;/gi, '"')
  .replace(/&#39;/gi, "'")

export const normalizeAnnotationExcerpt = value => typeof value === 'string'
  ? decodeExcerptEntities(value)
    .replace(/<\s*br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  : ''

const compactExcerpt = value => value.replace(/\s+/g, '')

const normalizeChineseText = value => {
  const t2s = getOpenCCConverter('t2s')
  return t2s ? t2s(value) : value
}

const rangeMatchesExcerpt = (range, expectedExcerpt) => {
  if (!range || range.collapsed) return false
  try {
    const actualExcerpt = normalizeAnnotationExcerpt(range.toString())
    if (actualExcerpt === expectedExcerpt
      || compactExcerpt(actualExcerpt) === compactExcerpt(expectedExcerpt)) {
      return true
    }
    const actualSimp = compactExcerpt(normalizeChineseText(actualExcerpt))
    const expectedSimp = compactExcerpt(normalizeChineseText(expectedExcerpt))
    return actualSimp.length > 0 && actualSimp === expectedSimp
  } catch {
    return false
  }
}

const getRangeStartTextOffset = (doc, range) => {
  const body = doc?.body ?? doc?.querySelector?.('body')
  if (!body || !range?.startContainer) return 0
  try {
    const prefix = doc.createRange()
    prefix.selectNodeContents(body)
    prefix.setEnd(range.startContainer, range.startOffset)
    return prefix.toString().length
  } catch {
    return 0
  }
}

export const buildRangeFingerprint = (range, length = 32) => {
  if (!range) return { prefix: '', suffix: '' }
  try {
    const startNode = range.startContainer
    const endNode = range.endContainer
    const doc = startNode?.ownerDocument ?? range.commonAncestorContainer?.ownerDocument
    if (!doc) return { prefix: '', suffix: '' }

    const blockTags = new Set([
      'P', 'DIV', 'LI', 'BLOCKQUOTE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'SECTION', 'ARTICLE', 'BODY'
    ])
    let container = range.commonAncestorContainer
    while (container && container !== doc.body && !blockTags.has(container.nodeName)) {
      container = container.parentNode
    }
    const boundaryNode = container ?? doc.body ?? doc.documentElement

    let prefix = ''
    try {
      const preRange = doc.createRange()
      preRange.selectNodeContents(boundaryNode)
      preRange.setEnd(startNode, range.startOffset)
      prefix = normalizeAnnotationExcerpt(preRange.toString()).slice(-length)
    } catch {
      prefix = ''
    }

    let suffix = ''
    try {
      const postRange = doc.createRange()
      postRange.selectNodeContents(boundaryNode)
      postRange.setStart(endNode, range.endOffset)
      suffix = normalizeAnnotationExcerpt(postRange.toString()).slice(0, length)
    } catch {
      suffix = ''
    }

    return { prefix, suffix }
  } catch {
    return { prefix: '', suffix: '' }
  }
}

export const calculateContextScore = (
  candidatePrefix,
  candidateSuffix,
  expectedPrefix,
  expectedSuffix
) => {
  const normCandPre = normalizeAnnotationExcerpt(candidatePrefix)
  const normCandSuf = normalizeAnnotationExcerpt(candidateSuffix)
  const normExpPre = normalizeAnnotationExcerpt(expectedPrefix)
  const normExpSuf = normalizeAnnotationExcerpt(expectedSuffix)

  const calcSim = (s1, s2) => {
    if (!s1 && !s2) return 1.0
    if (!s1 || !s2) return 0.0
    if (s1 === s2) return 1.0
    if (s1.endsWith(s2) || s2.endsWith(s1)) return 0.95
    if (s1.startsWith(s2) || s2.startsWith(s1)) return 0.95
    if (s1.includes(s2) || s2.includes(s1)) return 0.85

    const bigrams = str => {
      const set = new Map()
      for (let i = 0; i < str.length - 1; i++) {
        const bg = str.slice(i, i + 2)
        set.set(bg, (set.get(bg) ?? 0) + 1)
      }
      return set
    }
    const b1 = bigrams(s1)
    const b2 = bigrams(s2)
    let intersection = 0
    for (const [bg, count] of b1) {
      if (b2.has(bg)) intersection += Math.min(count, b2.get(bg))
    }
    const total = (s1.length - 1) + (s2.length - 1)
    if (total <= 0) return 0.0
    return (2.0 * intersection) / total
  }

  const prefixScore = calcSim(normCandPre, normExpPre)
  const suffixScore = calcSim(normCandSuf, normExpSuf)

  if (!normExpPre && !normExpSuf) {
    return 1.0
  }
  if (!normExpPre) {
    return suffixScore
  }
  if (!normExpSuf) {
    return prefixScore
  }
  return 0.5 * prefixScore + 0.5 * suffixScore
}

export const repairAnnotationTarget = async ({
  target,
  excerpt,
  prefix,
  suffix,
  resolveTarget,
  getDocument,
  findAllExcerptRanges,
  findExcerptRange,
  createTarget,
}) => {
  const expectedExcerpt = normalizeAnnotationExcerpt(excerpt)
  if (typeof target !== 'string' || !target || !expectedExcerpt) return target

  let resolved
  try {
    resolved = resolveTarget(target)
  } catch {
    return target
  }

  const { index, anchor } = resolved ?? {}
  if (!Number.isInteger(index) || index < 0 || typeof anchor !== 'function') {
    return target
  }

  let doc
  try {
    doc = await getDocument(index)
  } catch {
    return target
  }
  if (!doc) return target

  let currentRange
  try {
    currentRange = anchor(doc)
  } catch {
    currentRange = null
  }
  if (rangeMatchesExcerpt(currentRange, expectedExcerpt)) return target

  let bestCandidate = null
  let bestScore = -1

  const hasFingerprint = Boolean(
    normalizeAnnotationExcerpt(prefix) || normalizeAnnotationExcerpt(suffix)
  )

  if (hasFingerprint && typeof findAllExcerptRanges === 'function') {
    let candidates = []
    try {
      candidates = findAllExcerptRanges(doc, excerpt) ?? []
    } catch {
      candidates = []
    }

    for (const candidate of candidates) {
      const candRange = candidate?.range ?? candidate
      if (!rangeMatchesExcerpt(candRange, expectedExcerpt)) continue

      const fp = buildRangeFingerprint(candRange)
      const score = calculateContextScore(fp.prefix, fp.suffix, prefix, suffix)
      if (score > bestScore) {
        bestScore = score
        bestCandidate = candRange
      }
    }
  }

  if (!bestCandidate && typeof findExcerptRange === 'function') {
    try {
      const preferredOffset = getRangeStartTextOffset(doc, currentRange)
      const recoveredRange = findExcerptRange(doc, excerpt, preferredOffset)?.range
      if (rangeMatchesExcerpt(recoveredRange, expectedExcerpt)) {
        bestCandidate = recoveredRange
        bestScore = 1.0
      }
    } catch {
      // ignore
    }
  }

  if (!bestCandidate || bestScore < 0.7) {
    return target
  }

  try {
    return createTarget(index, bestCandidate) || target
  } catch {
    return target
  }
}

