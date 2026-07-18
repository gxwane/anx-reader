const getDocumentBody = doc => doc?.body ?? doc?.querySelector?.('body') ?? null

const collectTextNodes = root => {
  const nodes = []
  const walker = root.ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  while (walker.nextNode()) nodes.push(walker.currentNode)
  return nodes
}

export const createTextRangeFromOffsets = (doc, start, end = start) => {
  const body = getDocumentBody(doc)
  if (!body || !Number.isFinite(start) || !Number.isFinite(end)) return null

  const safeStart = Math.max(0, start)
  const safeEnd = Math.max(safeStart, end)
  const nodes = collectTextNodes(body)
  // Text ranges are half-open. At a node boundary, the start belongs to the
  // next node while the end belongs to the previous one. A collapsed range
  // uses the next node for both ends so virtual-chapter ownership is stable.
  const findPosition = (offset, preferNext) => {
    let cursor = 0
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index]
      const length = node.textContent.length
      const nodeEnd = cursor + length
      const isLast = index === nodes.length - 1
      if (offset >= cursor && (offset < nodeEnd
        || (!preferNext && offset === nodeEnd)
        || (isLast && offset === nodeEnd))) {
        return { node, offset: Math.min(length, offset - cursor) }
      }
      cursor = nodeEnd
    }
    return null
  }

  const startPosition = findPosition(safeStart, true)
  const endPosition = findPosition(safeEnd, safeStart === safeEnd)
  if (!startPosition || !endPosition) return null

  const range = doc.createRange()
  range.setStart(startPosition.node, startPosition.offset)
  range.setEnd(endPosition.node, endPosition.offset)
  return range
}
