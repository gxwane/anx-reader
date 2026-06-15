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

const getHrefFragment = href => {
  const index = href?.indexOf('#') ?? -1
  if (index < 0) return ''
  try {
    return decodeURIComponent(href.slice(index + 1)).trim()
  } catch {
    return href.slice(index + 1).trim()
  }
}

const getMarkerText = a => a?.textContent?.replace(/\s+/g, ' ').trim() ?? ''

const isNumberedMarker = text => /^\[?\d{1,4}\]?$/.test(text)

export const isGeneratedBacklinkHref = href => /^fn\d+$/i.test(getHrefFragment(href))

export const isGeneratedFootnoteHref = href => /^ft\d+$/i.test(getHrefFragment(href))

export const isNumberedNoteMarker = a => isNumberedMarker(getMarkerText(a))

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

  if (isNumberedNoteMarker(a) && isGeneratedBacklinkHref(href)) return false
  if (isNumberedNoteMarker(a) && isGeneratedFootnoteHref(href)) return true

  return isSuper(a)
    || (a?.children?.length === 1 && isSuper(a.children[0]))
    || isSuper(a?.parentElement)
}
