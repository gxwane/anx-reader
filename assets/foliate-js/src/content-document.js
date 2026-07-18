export const XHTML_MEDIA_TYPE = 'application/xhtml+xml'
export const HTML_MEDIA_TYPE = 'text/html'

const getParserError = doc => doc?.querySelector?.('parsererror') ?? null

export const parseContentDocument = (source, mediaType, parser = new DOMParser()) => {
  let document = parser.parseFromString(source, mediaType)
  const parserError = getParserError(document)
  const invalidXHTML = mediaType === XHTML_MEDIA_TYPE
    && (parserError || !document.documentElement?.namespaceURI)

  if (!invalidXHTML) {
    return {
      document,
      mediaType,
      recoveredFromInvalidXHTML: false,
      parserErrorMessage: null,
    }
  }

  const parserErrorMessage = parserError?.textContent?.trim()
    || parserError?.innerText?.trim()
    || 'Invalid XHTML'
  document = parser.parseFromString(source, HTML_MEDIA_TYPE)
  return {
    document,
    mediaType: HTML_MEDIA_TYPE,
    recoveredFromInvalidXHTML: true,
    parserErrorMessage,
  }
}

export const serializeContentDocument = doc =>
  new XMLSerializer().serializeToString(doc)
