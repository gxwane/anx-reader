import * as CFI from './epubcfi.js'
import { TOCProgress, SectionProgress } from './progress.js'
import { Overlayer } from './overlayer.js'
import { textWalker } from './text-walker.js'
import { Translator, TranslationMode } from './translator.js'
import { isExplicitNoteRef } from './noteref.js'
import { isRangeInHiddenVirtualChapter } from './virtual-chapter.js'
const { TTS } = await import('./tts.js')

const SEARCH_PREFIX = 'foliate-search:'
const interactiveViewClickCooldownMs = 900
const noteRefTouchAttr = 'data-anx-note-ref'
const interactiveClickSelector = [
  'a[href]',
  'button',
  'input',
  'select',
  'textarea',
  'summary',
  'label',
  '[role="button"]',
  '[contenteditable="true"]',
  'audio[controls]',
  'video[controls]',
].join(', ')

const getEventTargetElement = target =>
  target?.nodeType === 1 ? target : target?.parentElement

const suppressInteractiveTurn = doc => {
  if (!doc) return 0
  const suppressUntil = Date.now() + interactiveViewClickCooldownMs
  globalThis.__anxSuppressTouchTurnUntil = Math.max(
    globalThis.__anxSuppressTouchTurnUntil ?? 0,
    suppressUntil,
  )
  return suppressUntil
}

const suppressInteractiveClick = doc => {
  if (!doc) return
  const now = Date.now()
  const suppressUntil = suppressInteractiveTurn(doc)
  doc.__anxSuppressClick = true
  doc.__anxInteractiveClickAt = now
  doc.__anxSuppressViewClickUntil = suppressUntil
  globalThis.__anxInteractiveClickAt = now
  globalThis.__anxSuppressViewClickUntil = Math.max(
    globalThis.__anxSuppressViewClickUntil ?? 0,
    suppressUntil,
  )
  if (doc.__anxSuppressClickTimer) clearTimeout(doc.__anxSuppressClickTimer)
  doc.__anxSuppressClickTimer = setTimeout(() => {
    doc.__anxSuppressClick = false
    doc.__anxSuppressClickTimer = null
  }, interactiveViewClickCooldownMs)
}

class History extends EventTarget {
  #arr = []
  #index = -1
  pushState(x) {
    const last = this.#arr[this.#index]
    if (last === x || last?.fraction && last.fraction === x.fraction) return
    this.#arr[++this.#index] = x
    this.#arr.length = this.#index + 1
    this.dispatchEvent(new Event('index-change'))
    this.dispatchEvent(new CustomEvent('pushstate', { detail: x }))
  }
  replaceState(x) {
    const index = this.#index
    this.#arr[index] = x
  }
  back() {
    const index = this.#index
    if (index <= 0) return
    const detail = { state: this.#arr[index - 1] }
    this.#index = index - 1
    this.dispatchEvent(new CustomEvent('popstate', { detail }))
    this.dispatchEvent(new Event('index-change'))
  }
  forward() {
    const index = this.#index
    if (index >= this.#arr.length - 1) return
    const detail = { state: this.#arr[index + 1] }
    this.#index = index + 1
    this.dispatchEvent(new CustomEvent('popstate', { detail }))
    this.dispatchEvent(new Event('index-change'))
  }
  get canGoBack() {
    return this.#index > 0
  }
  get canGoForward() {
    return this.#index < this.#arr.length - 1
  }
  clear() {
    this.#arr = []
    this.#index = -1
  }
}

const languageInfo = lang => {
  if (!lang) return {}
  try {
    const canonical =
      Intl.getCanonicalLocales(String(lang).replace(/_/g, '-'))[0] ?? 'en'
    const locale = new Intl.Locale(canonical)
    const isCJK = ['zh', 'ja', 'kr'].includes(locale.language)
    const direction = (locale.getTextInfo?.() ?? locale.textInfo)?.direction
    return { canonical, locale, isCJK, direction }
  } catch (e) {
    console.warn(e)
    return {}
  }
}

export class View extends HTMLElement {
  #root = this.attachShadow({ mode: 'open' })
  #sectionProgress
  #tocProgress
  #pageProgress
  #searchResults = new Map()
  #index
  isFixedLayout = false
  lastLocation
  history = new History()
  #lastCfi = null
  #translator = new Translator()
  constructor() {
    super()
    this.history.addEventListener('popstate', ({ detail }) => {
      const resolved = this.resolveNavigation(detail.state)
      this.renderer.goTo(resolved)
    })
  }
  async open(book) {
    this.book = book
    this.language = languageInfo(book.metadata?.language)

    if (book.splitTOCHref && book.getTOCFragment) {
      const ids = book.sections.map(s => s.id)
      this.#sectionProgress = new SectionProgress(book.sections, 1500, 1600)
      const splitHref = book.splitTOCHref.bind(book)
      const getFragment = book.getTOCFragment.bind(book)
      this.#tocProgress = new TOCProgress()
      await this.#tocProgress.init({
        toc: book.toc ?? [], ids, splitHref, getFragment
      })
      this.#pageProgress = new TOCProgress()
      await this.#pageProgress.init({
        toc: book.pageList ?? [], ids, splitHref, getFragment
      })
    }

    this.isFixedLayout = this.book.rendition?.layout === 'pre-paginated'
    if (this.isFixedLayout) {
      await import('./fixed-layout.js')
      this.renderer = document.createElement('foliate-fxl')
    } else {
      await import('./paginator.js')
      this.renderer = document.createElement('foliate-paginator')
    }
    this.renderer.setAttribute('exportparts', 'head,foot,filter')
    this.renderer.addEventListener('load', e => this.#onLoad(e.detail))
    this.renderer.addEventListener('relocate', e => this.#onRelocate(e.detail))
    this.renderer.addEventListener('create-overlayer', e =>
      e.detail.attach(this.#createOverlayer(e.detail)))
    this.renderer.open(book)
    this.#root.append(this.renderer)

    if (book.sections.some(section => section.mediaOverlay)) {
      book.media.activeClass ||= '-epub-media-overlay-active'
      const activeClass = book.media.activeClass
      this.mediaOverlay = book.getMediaOverlay()
      let lastActive
      this.mediaOverlay.addEventListener('highlight', e => {
        const resolved = this.resolveNavigation(e.detail.text)
        this.renderer.goTo(resolved)
          .then(() => {
            const { doc } = this.renderer.getContents()
              .find(x => x.index = resolved.index)
            const el = resolved.anchor(doc)
            el.classList.add(activeClass)
            lastActive = new WeakRef(el)
          })
      })
      this.mediaOverlay.addEventListener('unhighlight', () => {
        lastActive?.deref()?.classList?.remove(activeClass)
      })
    }
  }
  close() {
    this.renderer?.destroy()
    this.renderer?.remove()
    this.#sectionProgress = null
    this.#tocProgress = null
    this.#pageProgress = null
    this.#searchResults = new Map()
    this.lastLocation = null
    this.history.clear()
    this.tts = null
    this.mediaOverlay = null
    this.#translator?.destroy()
  }
  goToTextStart() {
    return this.goTo(this.book.landmarks
      ?.find(m => m.type.includes('bodymatter') || m.type.includes('text'))
      ?.href ?? this.book.sections.findIndex(s => s.linear !== 'no'))
  }
  async init({ lastLocation, showTextStart }) {
    const resolved = lastLocation ? this.resolveNavigation(lastLocation) : null
    if (resolved) {
      await this.renderer.goTo(resolved)
      this.history.pushState(lastLocation)
    }
    else if (showTextStart) await this.goToTextStart()
    else {
      this.history.pushState(0)
      await this.next()
    }
  }
  #emit(name, detail, cancelable) {
    return this.dispatchEvent(new CustomEvent(name, { detail, cancelable }))
  }
  #onRelocate({ reason, range, index, chapterIndex, fraction, size }) {
    this.#index = index
    const progress = this.#sectionProgress?.getProgress(index, fraction, size) ?? {}

    // For virtual chapter sections the DOM is sliced, so most fragment anchors used
    // by TOCProgress are absent. Use the virtual chapter's tocItem directly instead.
    const vcTocItem = this.book?.sections?.[index]?.virtualChapters?.[chapterIndex]?.tocItem
    const tocItem = vcTocItem ?? this.#tocProgress?.getProgress(index, range)
    const pageItem = this.#pageProgress?.getProgress(index, range)
    const cfi = this.getCFI(index, range)
    const totalPages = this.renderer.pages
      ? Math.max(1, this.renderer.pages - 2)
      : progress.section.total
    const rawCurrentPage = this.renderer.page ?? progress.section.current
    const currentPage = this.renderer.pages
      ? Math.max(1, Math.min(totalPages, rawCurrentPage))
      : rawCurrentPage
    const chapterLocation = {
      current: currentPage,
      total: totalPages
    }

    this.lastLocation = { ...progress, tocItem, pageItem, cfi, chapterIndex, range, chapterLocation }
    if (reason === 'snap' || reason === 'page' || reason === 'scroll') {
      // Store chapterIndex alongside CFI for virtual chapter sections
      const state = chapterIndex != null && chapterIndex > 0
        ? { cfi, chapterIndex }
        : cfi
      this.history.replaceState(state)
    }

    if (cfi && (!this.#lastCfi || cfi !== this.#lastCfi)) {
      this.#lastCfi = cfi
      this.#emit('relocate', this.lastLocation)
    }
  }

  #onLoad({ doc, index }) {
    // set language and dir if not already set
    doc.documentElement.lang ||= this.language.canonical ?? ''
    if (!this.language.isCJK)
      doc.documentElement.dir ||= this.language.direction ?? ''

    this.#handleLinks(doc, index)
    this.#handleClick(doc)
    this.#handleImage(doc)
    
    // Start translation observation for this document
    this.#translator.observeDocument(doc)
    
    this.#emit('load', { doc, index })
  }
  #handleLinks(doc, index) {
    const { book } = this
    const section = book.sections[index]
    let touchLink = null
    let touchMoved = false
    let touchStartX = 0
    let touchStartY = 0
    let ignoreClickUntil = 0

    const activateLink = (a, e) => {
      if (!a?.isConnected) return
      ignoreClickUntil = Date.now() + 500
      touchLink = null
      touchMoved = false
      suppressInteractiveClick(doc)
      e?.preventDefault?.()
      e?.stopPropagation?.()
      const href_ = a.getAttribute('href')
      const href = section?.resolveHref?.(href_) ?? href_
      if (book?.isExternal?.(href)) {
        Promise.resolve(this.#emit('external-link', { a, href }, true))
          .then(x => x ? globalThis.open(href, '_blank') : null)
          .catch(e => console.error(e))
      } else {
        Promise.resolve(this.#emit('link', { a, href }, true))
          .then(x => x ? this.goTo(href) : null)
          .catch(e => console.error(e))
      }
    }

    doc.__anxActivateLink = (a, e) => activateLink(a, e)

    if (!doc.getElementById('anx-note-ref-touch-style')) {
      const style = doc.createElement('style')
      style.id = 'anx-note-ref-touch-style'
      style.textContent = `
a[${noteRefTouchAttr}] {
  position: relative;
  z-index: 1;
  touch-action: none;
  -webkit-tap-highlight-color: transparent;
}
`
      doc.head?.append(style)
    }

    for (const a of doc.querySelectorAll('a[href]')) {
      if (isExplicitNoteRef(a)) a.setAttribute(noteRefTouchAttr, '')
      a.addEventListener('click', e => {
        if (Date.now() < ignoreClickUntil) {
          e.preventDefault()
          e.stopPropagation()
          return
        }
        activateLink(a, e)
      })
    }

    const resolveLink = target => {
      const a = target instanceof Element
        ? target.closest('a[href]')
        : target?.parentElement?.closest?.('a[href]')
      if (!a) return null
      return {
        a,
        forceActivate: a.hasAttribute(noteRefTouchAttr),
      }
    }

    doc.addEventListener('touchstart', e => {
      if (e.touches.length !== 1) return
      const touch = e.touches[0]
      const link = resolveLink(e.target)
      if (!link) return
      suppressInteractiveTurn(doc)
      touchLink = link
      touchMoved = false
      touchStartX = touch?.screenX ?? 0
      touchStartY = touch?.screenY ?? 0
      e.preventDefault()
      e.stopImmediatePropagation()
      e.stopPropagation()
    }, { capture: true, passive: false })

    doc.addEventListener('touchmove', e => {
      if (!touchLink) return
      const touch = e.touches?.[0] ?? e.changedTouches?.[0]
      if (touch && !touchLink.forceActivate) {
        const dx = Math.abs((touch.screenX ?? 0) - touchStartX)
        const dy = Math.abs((touch.screenY ?? 0) - touchStartY)
        if (dx > 12 || dy > 12) touchMoved = true
      }
      e.preventDefault()
      e.stopImmediatePropagation()
      e.stopPropagation()
    }, { capture: true, passive: false })

    doc.addEventListener('touchend', e => {
      if (!touchLink) return
      const { a, forceActivate } = touchLink
      touchLink = null
      e.preventDefault()
      e.stopImmediatePropagation()
      e.stopPropagation()
      if (forceActivate || !touchMoved) activateLink(a, e)
      else {
        touchMoved = false
      }
    }, { capture: true, passive: false })

    doc.addEventListener('touchcancel', e => {
      if (!touchLink) return
      touchLink = null
      touchMoved = false
      e.preventDefault()
      e.stopImmediatePropagation()
      e.stopPropagation()
    }, { capture: true, passive: false })
  }

  #handleImage(doc) {
    for (const img of doc.querySelectorAll('img')) {
      // disable for a link
      if (img.closest('a[href]')) continue;

      // prevent iOS long-press image preview / callout and disable dragging/selecting
      img.style.webkitTouchCallout = 'none'       // iOS long-press callout
      img.style.webkitUserSelect = 'none'
      img.style.userSelect = 'none'
      img.style.webkitUserDrag = 'none'
      img.draggable = false
      // also block contextmenu to be safe
      img.addEventListener('contextmenu', e => { e.preventDefault(); e.stopPropagation(); }, true);
      // Check if device supports touch (mobile/tablet)
      const isTouchDevice = 'ontouchstart' in window;
 
      if (isTouchDevice) {
        // For touch devices, implement longpress
        let longPressTimer;
        let longPressTriggered = false;
        const longPressDelay = 500; // 500ms for longpress
      
        img.addEventListener('touchstart', e => {
          longPressTriggered = false;
          longPressTimer = setTimeout(() => {
            longPressTriggered = true;
            this.#emit('click-image', { img });
          }, longPressDelay);
        });
      
        img.addEventListener('touchend', e => {
          clearTimeout(longPressTimer);
          // do not prevent here so a short tap will produce a normal click that can bubble
        });
      
        img.addEventListener('touchmove', e => {
          clearTimeout(longPressTimer);
        });
      
        // intercept the synthetic click after a longpress and suppress it;
        // allow normal clicks (short taps) to bubble
        img.addEventListener('click', e => {
          if (longPressTriggered) {
            e.preventDefault();
            e.stopPropagation();
            longPressTriggered = false;
          }
        }, true);
      } else {
        // For desktop devices, keep original click behavior
        img.addEventListener('click', e => {
          e.preventDefault()
          e.stopPropagation()
          this.#emit('click-image', { img })
        })
      }
    }
  }

  #handleClick(doc) {
    doc.addEventListener('click', e => {
      if (window.isFootNoteOpen() && !e.currentTarget.__isFootNote) {
        window.closeFootNote()
        return
      }

      if (doc.getSelection().type === "Range")
        return

      const target = getEventTargetElement(e.target)
      if (target?.closest?.(interactiveClickSelector)) {
        suppressInteractiveClick(doc)
        return
      }

      const position = doc.position
      const scale = doc.scale
      let { clientX, clientY } = e
      
      // if the position is not null, it is fixed layout
      if (position) {
        clientX *= scale
        clientY *= scale

        const docWidth = doc.documentElement.getBoundingClientRect().width * scale
        if (position === 'right' && docWidth * 2.2 < window.innerWidth) {
          clientX += window.innerWidth * 0.5
        }
        this.#emit('click-view', { x: clientX, y: clientY })
        return
      }
      
      const iframe = doc.defaultView?.frameElement
      if (iframe) {
        const rect = iframe.getBoundingClientRect()
        clientX += rect.left
        clientY += rect.top
      }

      this.#emit('click-view', { x: clientX, y: clientY })
    })
    this.renderer.addEventListener('click', e => {
      const target = getEventTargetElement(e.composedPath?.()[0])
      if (target?.tagName === 'IFRAME') return
      if (target?.closest?.(interactiveClickSelector)) return

      let { clientX, clientY } = e
      while (clientX > window.innerWidth) {
        clientX -= window.innerWidth
      }
      this.#emit('click-view', { x: clientX, y: clientY })
    })
  }
  async addAnnotation(annotation, remove) {
    const { value } = annotation
    if (value.startsWith(SEARCH_PREFIX)) {
      const cfi = value.replace(SEARCH_PREFIX, '')
      const { index, anchor } = await this.resolveNavigation(cfi)
      const obj = this.#getOverlayer(index)
      if (obj) {
        const { overlayer, doc } = obj
        if (remove) {
          overlayer.remove(value)
          return
        }
        const range = doc ? anchor(doc) : anchor
        if (!isRangeInHiddenVirtualChapter(range)) {
          overlayer.add(value, range, Overlayer.outline, { color: '#39c5bbaa' });
        }
      }
      return
    }
    const { index, anchor } = await this.resolveNavigation(value)
    const obj = this.#getOverlayer(index)
    if (obj) {
      const { overlayer, doc } = obj
      overlayer.remove(value)
      if (!remove) {
        const range = doc ? anchor(doc) : anchor
        if (!isRangeInHiddenVirtualChapter(range)) {
          const draw = (func, opts) => overlayer.add(value, range, func, opts)
          this.#emit('draw-annotation', { draw, annotation, doc, range })
        }
      }
    }
    const label = this.#tocProgress.getProgress(index)?.label ?? ''
    return { index, label }
  }
  deleteAnnotation(annotation) {
    return this.addAnnotation(annotation, true)
  }
  #getOverlayer(index) {
    return this.renderer.getContents()
      .find(x => x.index === index && x.overlayer)
  }
  #createOverlayer({ doc, index }) {
    const overlayer = new Overlayer(doc)
    doc.addEventListener('click', e => {
      const [value, range] = overlayer.hitTest(e)
      if (value && !value.startsWith(SEARCH_PREFIX)) {
        e.preventDefault()
        e.stopPropagation()
        this.#emit('show-annotation', { value, index, range })
      }
    }, true)

    const list = this.#searchResults.get(index)
    if (list) for (const item of list) this.addAnnotation(item)

    this.#emit('create-overlay', { index })
    return overlayer
  }
  async showAnnotation(annotation) {
    const { value } = annotation
    const resolved = await this.goTo(value)
    if (resolved) {
      const { index, anchor, chapterIndex } = resolved
      const obj = this.#getOverlayer(index, chapterIndex)
      if (obj) {
        const { doc } = obj
        const range = anchor(doc)
        this.#emit('show-annotation', { value, index, range })
      }
    }
  }
  getCFI(index, range) {
    const baseCFI = this.book.sections[index].cfi ?? CFI.fake.fromIndex(index)
    if (!range) return baseCFI
    return CFI.joinIndir(baseCFI, CFI.fromRange(range))
  }
  resolveCFI(cfi) {
    let resolved;
    if (this.book.resolveCFI) {
      resolved = this.book.resolveCFI(cfi)
    } else {
      const parts = CFI.parse(cfi)
      const index = CFI.fake.toIndex((parts.parent ?? parts).shift())
      const anchor = doc => CFI.toRange(doc, parts)
      resolved = { index, anchor }
    }
    // Virtual-chapter sections load the full document; the paginator's afterLoad
    // resolves the anchor against that intact DOM and auto-detects which virtual
    // chapter contains it (see #display autoResolveVChapters). No marker needed.
    return resolved;
  }
  resolveNavigation(target) {
    try {
      if (typeof target === 'number') return { index: target }
      if (typeof target === 'object' && target !== null) {
        if (typeof target.fraction === 'number') {
          const [index, anchor] = this.#sectionProgress.getSection(target.fraction)
          return { index, anchor }
        }
        // { cfi, chapterIndex } format for virtual chapter sections
        if (target.cfi) {
          const resolved = this.resolveCFI(target.cfi)
          if (target.chapterIndex != null) resolved.chapterIndex = target.chapterIndex
          return resolved
        }
      }
      if (typeof target === 'string') {
        if (CFI.isCFI.test(target)) return this.resolveCFI(target)
        return this.book.resolveHref(target)
      }
    } catch (e) {
      console.error(e)
      console.error(`Could not resolve target ${target}`)
    }
  }
  async goTo(target) {
    const resolved = this.resolveNavigation(target)
    try {
      await this.renderer.goTo(resolved)
      this.history.pushState(target)
      return resolved
    } catch (e) {
      console.error(e)
      console.error(`Could not go to ${target}`)
    }
  }
  async goToFraction(frac) {
    const [index, anchor] = this.#sectionProgress.getSection(frac)
    await this.renderer.goTo({ index, anchor })
    this.history.pushState({ fraction: frac })
  }
  async select(target) {
    try {
      const obj = await this.resolveNavigation(target)
      await this.renderer.goTo({ ...obj, select: true })
      this.history.pushState(target)
    } catch (e) {
      console.error(e)
      console.error(`Could not go to ${target}`)
    }
  }
  deselect() {
    for (const { doc } of this.renderer.getContents())
      doc.defaultView.getSelection().removeAllRanges()
  }
  getSectionFractions() {
    const hrefList = this.#tocProgress?.ids ?? []
    return (this.#sectionProgress?.sectionFractions ?? [])
    // .map(x => x + Number.EPSILON)
      .map((fraction, index) => ({
        fraction,
        href: hrefList[index] ?? '',
        index
      }))
  }
  getProgressOf(index, range) {
    const tocItem = this.#tocProgress?.getProgress(index, range)
    const pageItem = this.#pageProgress?.getProgress(index, range)
    return { tocItem, pageItem }
  }
  async getTOCItemOf(target) {
    try {
      const { index, anchor } = await this.resolveNavigation(target)
      const doc = await this.book.sections[index].createDocument()
      const frag = anchor(doc)
      const isRange = frag instanceof Range
      const range = isRange ? frag : doc.createRange()
      if (!isRange) range.selectNodeContents(frag)
      return this.#tocProgress.getProgress(index, range)
    } catch (e) {
      console.error(e)
      console.error(`Could not get ${target}`)
    }
  }
  async prev(distance) {
    await this.renderer.prev(distance)
  }
  async next(distance) {
    await this.renderer.next(distance)
  }
  goLeft() {
    return this.book.dir === 'rtl' ? this.next() : this.prev()
  }
  goRight() {
    return this.book.dir === 'rtl' ? this.prev() : this.next()
  }
  async * #searchSection(matcher, query, index) {
    const doc = await this.book.sections[index].createDocument()
    for (const { range, excerpt } of matcher(doc, query))
      yield { cfi: this.getCFI(index, range), excerpt }
  }
  async * #searchBook(matcher, query) {
    const { sections } = this.book
    for (const [index, { createDocument }] of sections.entries()) {
      if (!createDocument) continue
      const doc = await createDocument()
      const subitems = Array.from(matcher(doc, query), ({ range, excerpt }) =>
        ({ cfi: this.getCFI(index, range), excerpt }))
      const progress = (index + 1) / sections.length
      yield { progress }
      if (subitems.length) yield { index, subitems }
    }
  }
  async * search(opts) {
    console.log('search', opts)
    this.clearSearch()
    const { searchMatcher } = await import('./search.js')
    const { query, index } = opts
    const matcher = searchMatcher(textWalker,
      { defaultLocale: this.language, ...opts })
    const iter = index != null
      ? this.#searchSection(matcher, query, index)
      : this.#searchBook(matcher, query)

    const list = []
    this.#searchResults.set(index, list)

    for await (const result of iter) {
      if (result.subitems) {
        const list = result.subitems
          .map(({ cfi }) => ({ value: SEARCH_PREFIX + cfi }))
        this.#searchResults.set(result.index, list)
        for (const item of list) this.addAnnotation(item)
        yield {
          label: this.#tocProgress.getProgress(result.index)?.label ?? '',
          subitems: result.subitems,
        }
      }
      else {
        if (result.cfi) {
          const item = { value: SEARCH_PREFIX + result.cfi }
          list.push(item)
          this.addAnnotation(item)
        }
        yield result
      }
    }
    yield 'done'
  }
  clearSearch() {
    for (const list of this.#searchResults.values())
      for (const item of list) this.deleteAnnotation(item)
    this.#searchResults.clear()
  }
  oldValue = null
  initTTS(stop) {
    if (stop)
      return this.#getOverlayer(this.#index)?.overlayer.remove(this.oldValue)

    const doc = this.renderer.getContents()[0].doc;
    if (this.tts && this.tts.doc === doc) return;
    this.tts = new TTS(
      doc,
      textWalker,
      (range) => {
        const obj = this.#getOverlayer(this.#index);
        let value = null;
        if (obj) {
          const { overlayer } = obj;
          if (this.oldValue) {
            overlayer.remove(this.oldValue);
          }
          value = this.getCFI(this.#index, range);
          overlayer.add(value, range, Overlayer.highlight, { color: '#39c5bc83' });
          this.oldValue = value;
        }
        this.renderer.scrollToAnchor(range);
        return value;
      },
      (range) => this.getCFI(this.#index, range),
    );
  }
  startMediaOverlay() {
    const { index } = this.renderer.getContents()[0]
    return this.mediaOverlay.start(index)
  }
  
  // Translation control methods
  setTranslationMode(mode) {
    this.#translator.setTranslationMode(mode)
  }
  
  getTranslationMode() {
    return this.#translator.getTranslationMode()
  }
  
  clearTranslations() {
    this.#translator.clearTranslations()
  }
}

customElements.define('foliate-view', View)
