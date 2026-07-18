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

const rangeMatchesExcerpt = (range, expectedExcerpt) => {
  if (!range || range.collapsed) return false
  try {
    const actualExcerpt = normalizeAnnotationExcerpt(range.toString())
    return actualExcerpt === expectedExcerpt
      || compactExcerpt(actualExcerpt) === compactExcerpt(expectedExcerpt)
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

export const repairAnnotationTarget = async ({
  target,
  excerpt,
  resolveTarget,
  getDocument,
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

  let recoveredRange
  try {
    const preferredOffset = getRangeStartTextOffset(doc, currentRange)
    recoveredRange = findExcerptRange(doc, excerpt, preferredOffset)?.range
  } catch {
    return target
  }
  if (!rangeMatchesExcerpt(recoveredRange, expectedExcerpt)) return target

  try {
    return createTarget(index, recoveredRange) || target
  } catch {
    return target
  }
}
