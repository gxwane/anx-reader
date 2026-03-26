const explicitNoteRefClasses = [
  'noteref',
  'note-ref',
  'footnote-ref',
  'endnote-ref',
  'biblioref',
  'biblio-ref',
  'glossref',
  'gloss-ref',
]

const explicitNoteRefTokens = new Set([
  'noteref',
  'doc-noteref',
  'biblioref',
  'doc-biblioref',
  'glossref',
  'doc-glossref',
])

const backlinkTokens = new Set(['backlink', 'doc-backlink'])

const hasAnyToken = (tokens, candidates) => {
  for (const candidate of candidates) {
    if (tokens.has(candidate)) return true
  }
  return false
}

const getLinkTokens = el => new Set([
  el?.getAttributeNS?.('http://www.idpf.org/2007/ops', 'type'),
  el?.getAttribute?.('epub:type'),
  el?.getAttribute?.('type'),
  el?.getAttribute?.('role'),
]
  .filter(value => typeof value === 'string' && value.trim())
  .flatMap(value => value.trim().toLowerCase().split(/\s+/)))

const hasFragmentHref = href =>
  typeof href === 'string'
  && href.includes('#')
  && !/^[a-z][a-z\d+.-]*:/i.test(href.trim())

const isSuper = el => {
  if (!(el instanceof Element)) return false
  const { verticalAlign } = getComputedStyle(el)
  return verticalAlign === 'super' || /^\d/.test(verticalAlign)
}

export const isExplicitNoteRef = a => {
  const href = a?.getAttribute?.('href')?.trim()
  if (!hasFragmentHref(href)) return false

  const tokens = getLinkTokens(a)
  if (hasAnyToken(tokens, explicitNoteRefTokens)) return true

  return explicitNoteRefClasses.some(cls => a?.classList?.contains?.(cls))
}

export const isHeuristicNoteRef = a => {
  const href = a?.getAttribute?.('href')?.trim()
  if (!hasFragmentHref(href)) return false

  const tokens = getLinkTokens(a)
  if (hasAnyToken(tokens, backlinkTokens)) return false

  return isSuper(a)
    || (a?.children?.length === 1 && isSuper(a.children[0]))
    || isSuper(a?.parentElement)
}
