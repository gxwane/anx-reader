import { isExplicitNoteRef, isHeuristicNoteRef } from './noteref.js'

const getTypes = el => new Set(el?.getAttributeNS?.('http://www.idpf.org/2007/ops', 'type')?.split(' '))
const getRoles = el => new Set(el?.getAttribute?.('role')?.split(' '))

const getReferencedType = el => {
    const types = getTypes(el)
    const roles = getRoles(el)
    return roles.has('doc-biblioentry') || types.has('biblioentry') ? 'biblioentry'
        : roles.has('definition') || types.has('glossdef') ? 'definition'
            : roles.has('doc-endnote') || types.has('endnote') || types.has('rearnote') ? 'endnote'
                : roles.has('doc-footnote') || types.has('footnote') ? 'footnote'
                    : roles.has('note') || types.has('note') ? 'note' : null
}

const isInline = 'a, span, sup, sub, em, strong, i, b, small, big'
const extractFootnote = (doc, anchor) => {
    let el = anchor(doc)
    const target = el
    while (el.matches(isInline)) {
        const parent = el.parentElement
        if (!parent) break
        el = parent
    }
    if (el === doc.body) {
        const sibling = target.nextElementSibling
        if (sibling && !sibling.matches(isInline)) return sibling
        throw new Error('Failed to extract footnote')
    }
    return el
}

export class FootnoteHandler extends EventTarget {
    detectFootnotes = true
    #showFragment(book, { index, anchor }, href) {
        const view = document.createElement('foliate-view')
        return new Promise((resolve, reject) => {
            view.addEventListener('load', e => {
                try {
                    const { doc } = e.detail
                    const el = anchor(doc)
                    const type = getReferencedType(el)
                    const hidden = el?.matches?.('aside') && type === 'footnote'
                    if (el) {
                        const range = el.startContainer ? el : doc.createRange()
                        if (!el.startContainer) {
                            if (el.matches('li, aside')) range.selectNodeContents(el)
                            else range.selectNode(el)
                        }
                        const frag = range.extractContents()
                        doc.body.replaceChildren()
                        doc.body.appendChild(frag)
                    }
                    const detail = { view, href, type, hidden, target: el }
                    this.dispatchEvent(new CustomEvent('render', { detail }))
                    resolve()
                } catch (e) {
                    reject(e)
                }
            })
            view.open(book)
                .then(() => this.dispatchEvent(new CustomEvent('before-render', { detail: { view } })))
                .then(() => view.goTo(index))
                .catch(reject)
        })
    }
    handle(book, e) {
        const { a, href } = e.detail
        const isExplicit = isExplicitNoteRef(a)
        const isHeuristic = this.detectFootnotes && isHeuristicNoteRef(a)
        if (!isExplicit && !isHeuristic) return

        e.preventDefault()
        if (isExplicit) {
            return Promise.resolve(book.resolveHref(href)).then(target =>
                this.#showFragment(book, target, href))
        }

        return Promise.resolve(book.resolveHref(href)).then(({ index, anchor }) => {
            const target = { index, anchor: doc => extractFootnote(doc, anchor) }
            return this.#showFragment(book, target, href)
        })
    }
}
