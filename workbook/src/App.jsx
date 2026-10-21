import { memo, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { PageFlip } from 'page-flip'
import { PAGES, SECTIONS, CONTENTS_LINKS, PAGE_W, PAGE_H } from './pages.js'

const RATIO = PAGE_W / PAGE_H
const TOTAL = PAGES.length
const PDF_URL = '/Memory-Meter-Workbook.pdf'
// 이보다 좁은 화면(폰 세로)에서만 자동으로 한 쪽 보기
const AUTO_SPREAD_MIN_W = 520
// StPageFlip goes portrait when the block is narrower than 2 × minWidth
const MIN_PAGE_W = { spread: 100, single: 100000 }

// 해시(#/12)로 특정 페이지를 바로 열 수 있게 — 공유 링크용
function pageFromHash() {
  const n = parseInt(window.location.hash.replace(/^#\/?/, ''), 10)
  return Number.isFinite(n) && n >= 1 && n <= TOTAL ? n - 1 : 0
}

// Content box of the stage, re-measured on resize.
function useStageSize(stageRef) {
  const [size, setSize] = useState({ w: 0, h: 0 })
  useLayoutEffect(() => {
    const el = stageRef.current
    const measure = () => {
      const cs = getComputedStyle(el)
      setSize({
        w: el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight),
        h: el.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom),
      })
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [stageRef])
  return size
}

// 책 너비: 양면이면 펼침면(2쪽), 아니면 1쪽이 스테이지에 꽉 차게
function bookWidthFor({ w, h }, spread) {
  return Math.floor(spread ? Math.min(w, h * RATIO * 2) : Math.min(w, h * RATIO))
}

// StPageFlip moves and removes the page nodes it is given, so the pages are built here
// outside React; that keeps remounts (HMR, StrictMode) safe.
function buildPages(root) {
  return PAGES.map((p) => {
    const page = document.createElement('div')
    page.className = 'page'
    page.dataset.density = p.n === 1 || p.n === TOTAL ? 'hard' : 'soft'
    const img = document.createElement('img')
    img.src = p.src
    img.alt = `Page ${p.n}: ${p.title}`
    img.draggable = false
    // No lazy loading: StPageFlip only shows a page mid-flip, so a lazy image lands blank.
    // The whole book is ~5 MB, so fetch it all, the first spreads first.
    img.decoding = 'async'
    if (p.n > 6) img.fetchPriority = 'low'
    page.append(img)
    if (p.n === 3) {
      const links = document.createElement('div')
      links.className = 'toc-links'
      for (const l of CONTENTS_LINKS) {
        const btn = document.createElement('button')
        btn.type = 'button'
        btn.className = 'toc-link'
        btn.style.top = `${l.top}%`
        btn.style.height = `${l.height}%`
        btn.dataset.page = l.page
        btn.setAttribute('aria-label', `Go to ${l.label}, page ${l.page}`)
        links.append(btn)
      }
      page.append(links)
    }
    root.append(page)
    return page
  })
}

const Book = memo(function Book({ spread, startPage, onReady, onFlip, onState }) {
  const hostRef = useRef(null)

  useEffect(() => {
    const host = hostRef.current
    const el = document.createElement('div')
    host.append(el)
    const pages = buildPages(el)
    const flip = new PageFlip(el, {
      width: PAGE_W,
      height: PAGE_H,
      size: 'stretch',
      minWidth: MIN_PAGE_W[spread ? 'spread' : 'single'],
      maxWidth: 1000,
      minHeight: 300,
      maxHeight: 1600,
      showCover: true,
      usePortrait: true,
      autoSize: true,
      maxShadowOpacity: 0.45,
      flippingTime: 800,
      mobileScrollSupport: false,
      startPage,
    })
    flip.loadFromHTML(pages)
    flip.on('flip', (e) => onFlip(e.data))
    flip.on('changeState', (e) => onState(e.data))
    onReady(flip)
    return () => {
      flip.destroy()
      host.replaceChildren()
    }
    // startPage is only read on mount; the parent remounts Book (key) when the layout changes
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spread, onReady, onFlip, onState])

  return <div className="book-host" ref={hostRef} />
})

function spreadLabel(index, portrait) {
  const n = index + 1
  if (portrait || n === 1 || n === TOTAL) return String(n).padStart(2, '0')
  // showCover: spreads are (2,3), (4,5) …
  const left = n % 2 === 0 ? n : n - 1
  return `${String(left).padStart(2, '0')}–${String(left + 1).padStart(2, '0')}`
}

export default function App() {
  const flipRef = useRef(null)
  const stageRef = useRef(null)
  const stage = useStageSize(stageRef)
  const [layout, setLayout] = useState(() => {
    try { return localStorage.getItem('workbook-layout') || 'auto' } catch { return 'auto' }
  })
  const spread = layout === 'auto' ? stage.w >= AUTO_SPREAD_MIN_W : layout === 'spread'
  const bookWidth = bookWidthFor(stage, spread)
  const [index, setIndex] = useState(pageFromHash)
  const indexRef = useRef(index)
  indexRef.current = index
  const [flipping, setFlipping] = useState(false)
  const [portrait, setPortrait] = useState(false)
  const [gridOpen, setGridOpen] = useState(false)
  const [zoom, setZoom] = useState(null)
  const [opened, setOpened] = useState(pageFromHash() > 0)

  const onReady = useCallback((flip) => {
    flipRef.current = flip
    setPortrait(flip.getOrientation() === 'portrait')
    flip.on('changeOrientation', (e) => setPortrait(e.data === 'portrait'))
  }, [])
  const onFlip = useCallback((i) => {
    setIndex(i)
    setOpened(true)
    history.replaceState(null, '', i === 0 ? '#' : `#/${i + 1}`)
  }, [])
  const onState = useCallback((s) => setFlipping(s !== 'read'), [])

  // 1쪽/2쪽 토글 — 선택은 이 브라우저에만 기억
  const toggleLayout = useCallback(() => {
    setLayout(() => {
      const nextLayout = spread ? 'single' : 'spread'
      try { localStorage.setItem('workbook-layout', nextLayout) } catch { /* private mode */ }
      return nextLayout
    })
  }, [spread])

  // StPageFlip only re-measures on window resize; the wrapper width is set after that.
  useLayoutEffect(() => {
    flipRef.current?.getUI().update()
  }, [bookWidth])

  // 주소창에서 #/n 을 직접 바꿔도 그 페이지로
  useEffect(() => {
    const onHash = () => {
      const target = pageFromHash()
      const flip = flipRef.current
      if (!flip || target === flip.getCurrentPageIndex()) return
      flip.turnToPage(target)
      setIndex(flip.getCurrentPageIndex())
      setOpened(true)
    }
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const go = useCallback((n) => {
    const flip = flipRef.current
    if (!flip) return
    const target = Math.max(0, Math.min(TOTAL - 1, n))
    const cur = flip.getCurrentPageIndex()
    // 한두 장 거리는 넘기는 애니메이션, 멀리 점프는 바로 이동 후 마지막 한 장만 넘김
    if (Math.abs(target - cur) <= 2) flip.flip(target, 'top')
    else {
      flip.turnToPage(target > cur ? Math.max(0, target - 2) : Math.min(TOTAL - 1, target + 2))
      requestAnimationFrame(() => flip.flip(target, 'top'))
    }
  }, [])
  const next = useCallback(() => flipRef.current?.flipNext('top'), [])
  const prev = useCallback(() => flipRef.current?.flipPrev('top'), [])

  // Contents page hotspots: StPageFlip forwards clicks on <button> (clickEventForward).
  useEffect(() => {
    const onClick = (e) => {
      const btn = e.target.closest?.('.toc-link')
      if (btn) go(Number(btn.dataset.page) - 1)
    }
    document.addEventListener('click', onClick)
    return () => document.removeEventListener('click', onClick)
  }, [go])

  useEffect(() => {
    const onKey = (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (zoom !== null) {
        if (e.key === 'Escape') setZoom(null)
        if (e.key === 'ArrowRight') setZoom((z) => Math.min(TOTAL - 1, z + 1))
        if (e.key === 'ArrowLeft') setZoom((z) => Math.max(0, z - 1))
        return
      }
      if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') { e.preventDefault(); next() }
      else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); prev() }
      else if (e.key === 'Home') go(0)
      else if (e.key === 'End') go(TOTAL - 1)
      else if (e.key === 'g') setGridOpen((v) => !v)
      else if (e.key === 'z') setZoom(index)
      else if (e.key === 'f') toggleFullscreen()
      else if (e.key === 'd') toggleLayout()
      else if (e.key === 'Escape') setGridOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [next, prev, go, index, zoom, toggleLayout])

  const current = PAGES[index]
  const section = SECTIONS.find((s) => s.id === current.section)

  // 모바일에서 칩 줄이 가로 스크롤되니 현재 섹션 칩을 보이게
  useEffect(() => {
    document.querySelector('.chip.is-active')?.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' })
  }, [section.id])
  const progress = index / (TOTAL - 1)

  return (
    <div className={`app ${opened ? 'is-open' : ''}`}>
      <header className="topbar">
        <a className="brand" href="#" onClick={(e) => { e.preventDefault(); go(0) }}>
          <img className="brand-mark" src="/mm-icon.png" alt="" width="28" height="28" />
          <span>Memory Meter</span>
          <span className="brand-sub">Workbook · Group 6</span>
        </a>
        <nav className="sections" aria-label="Sections">
          {SECTIONS.map((s) => (
            <button
              key={s.id}
              type="button"
              className={`chip ${s.id === section.id ? 'is-active' : ''}`}
              onClick={() => go(s.start - 1)}
            >
              {s.label}
            </button>
          ))}
        </nav>
        <div className="tools">
          {/* 워크북 PDF 원본 전체 다운로드 */}
          <a
            className="download-btn"
            href={PDF_URL}
            download="Memory-Meter-Workbook.pdf"
            aria-label="Download the workbook as PDF (34 MB)"
            title="Download PDF (34 MB)"
          >
            <svg viewBox="0 0 24 24"><path d="M12 4v11M7 10.5l5 5 5-5M5 19.5h14" /></svg>
            <span>PDF</span>
          </a>
          <button type="button" className="icon-btn" onClick={() => setZoom(index)} aria-label="Read this page up close (Z)" title="Zoom (Z)">
            <svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5" /><path d="M15.5 15.5 21 21M10.5 7.5v6M7.5 10.5h6" /></svg>
          </button>
          <button
            type="button"
            className="icon-btn layout-btn"
            onClick={toggleLayout}
            aria-label={spread ? 'Show one page (D)' : 'Show two pages (D)'}
            title={spread ? 'One page (D)' : 'Two pages (D)'}
          >
            {spread
              ? <svg viewBox="0 0 24 24"><rect x="7" y="4" width="10" height="16" rx="1" /></svg>
              : <svg viewBox="0 0 24 24"><path d="M12 6.5C10 5 7 4.5 3.5 5v13c3.5-.5 6.5 0 8.5 1.5M12 6.5C14 5 17 4.5 20.5 5v13c-3.5-.5-6.5 0-8.5 1.5M12 6.5v13" /></svg>}
          </button>
          <button type="button" className="icon-btn" onClick={() => setGridOpen(true)} aria-label="All pages (G)" title="All pages (G)">
            <svg viewBox="0 0 24 24"><rect x="4" y="4" width="6.5" height="6.5" rx="1" /><rect x="13.5" y="4" width="6.5" height="6.5" rx="1" /><rect x="4" y="13.5" width="6.5" height="6.5" rx="1" /><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1" /></svg>
          </button>
          <button type="button" className="icon-btn hide-sm" onClick={toggleFullscreen} aria-label="Fullscreen (F)" title="Fullscreen (F)">
            <svg viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" /></svg>
          </button>
        </div>
      </header>

      <main className="stage" ref={stageRef}>
        <button type="button" className="nav-arrow left" onClick={prev} disabled={index === 0} aria-label="Previous page">
          <svg viewBox="0 0 24 24"><path d="M15 5 8 12l7 7" /></svg>
        </button>
        <div
          className={`book-wrap ${portrait ? 'is-portrait' : ''} ${flipping ? 'is-flipping' : ''} ${!portrait && index === 0 ? 'at-cover' : ''} ${!portrait && index === TOTAL - 1 ? 'at-back' : ''}`}
          style={{ width: bookWidth || undefined }}
        >
          {stage.w > 0 && <Book
            key={spread ? 'spread' : 'single'}
            spread={spread}
            startPage={indexRef.current}
            onReady={onReady}
            onFlip={onFlip}
            onState={onState}
          />}
        </div>
        <button type="button" className="nav-arrow right" onClick={next} disabled={index >= TOTAL - 1} aria-label="Next page">
          <svg viewBox="0 0 24 24"><path d="m9 5 7 7-7 7" /></svg>
        </button>
        {!opened && <p className="hint">Drag a corner or press → to open</p>}
      </main>

      <footer className="dock">
        <div className="dock-nav">
          <button type="button" className="dock-btn" onClick={prev} disabled={index === 0} aria-label="Previous page">
            <svg viewBox="0 0 24 24"><path d="M15 5 8 12l7 7" /></svg>
          </button>
          <div className="dock-meta">
            <span className="dock-page">{spreadLabel(index, portrait)}<small> / {TOTAL}</small></span>
            <span className="dock-title">{current.title}</span>
          </div>
          <button type="button" className="dock-btn" onClick={next} disabled={index >= TOTAL - 1} aria-label="Next page">
            <svg viewBox="0 0 24 24"><path d="m9 5 7 7-7 7" /></svg>
          </button>
        </div>
        <Ruler index={index} progress={progress} onSeek={go} />
      </footer>

      {gridOpen && <Grid index={index} onPick={(i) => { setGridOpen(false); go(i) }} onClose={() => setGridOpen(false)} />}
      {zoom !== null && <Zoom index={zoom} onChange={setZoom} onClose={() => setZoom(null)} />}
    </div>
  )
}

function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen?.()
  else document.documentElement.requestFullscreen?.()
}

// 하단 줄자 스크러버 — 키 재는 벽 눈금 모티프. 페이지 1장 = 눈금 1칸
function Ruler({ index, progress, onSeek }) {
  const ref = useRef(null)
  const [hover, setHover] = useState(null)
  const pick = (clientX) => {
    const r = ref.current.getBoundingClientRect()
    const t = Math.max(0, Math.min(1, (clientX - r.left) / r.width))
    return Math.round(t * (TOTAL - 1))
  }
  const dragging = useRef(false)
  return (
    <div className="ruler-wrap">
      <div
        ref={ref}
        className="ruler"
        role="slider"
        tabIndex={0}
        aria-label="Page"
        aria-valuemin={1}
        aria-valuemax={TOTAL}
        aria-valuenow={index + 1}
        onPointerDown={(e) => { dragging.current = true; e.currentTarget.setPointerCapture(e.pointerId); setHover(pick(e.clientX)) }}
        onPointerMove={(e) => setHover(pick(e.clientX))}
        onPointerUp={(e) => { if (dragging.current) onSeek(pick(e.clientX)); dragging.current = false }}
        onPointerLeave={() => { if (!dragging.current) setHover(null) }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') e.stopPropagation()
          if (e.key === 'ArrowRight') onSeek(index + 1)
          if (e.key === 'ArrowLeft') onSeek(index - 1)
        }}
      >
        <div className="ruler-fill" style={{ width: `${progress * 100}%` }} />
        {PAGES.map((p, i) => (
          <span
            key={p.n}
            className={`tick ${SECTIONS.some((s) => s.start === p.n) ? 'is-major' : ''} ${i <= index ? 'is-past' : ''}`}
            style={{ left: `${(i / (TOTAL - 1)) * 100}%` }}
          />
        ))}
        {SECTIONS.map((s) => (
          <span key={s.id} className="ruler-label" style={{ left: `${((s.start - 1) / (TOTAL - 1)) * 100}%` }}>
            {s.label}
          </span>
        ))}
        <span className="ruler-thumb" style={{ left: `${progress * 100}%` }} />
        {hover !== null && (
          <span className="ruler-peek" style={{ left: `${(hover / (TOTAL - 1)) * 100}%` }}>
            <img src={PAGES[hover].src} alt="" />
            <span>{String(hover + 1).padStart(2, '0')} · {PAGES[hover].title}</span>
          </span>
        )}
      </div>
    </div>
  )
}

function Grid({ index, onPick, onClose }) {
  return (
    <div className="overlay" role="dialog" aria-modal="true" aria-label="All pages" onClick={onClose}>
      <div className="grid-panel" onClick={(e) => e.stopPropagation()}>
        <div className="grid-head">
          <h2>All pages</h2>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close">
            <svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18" /></svg>
          </button>
        </div>
        {SECTIONS.map((s) => (
          <section key={s.id} className="grid-section">
            <h3>{s.label}<span>{String(s.start).padStart(2, '0')}–{String(s.end).padStart(2, '0')}</span></h3>
            <div className="grid">
              {PAGES.filter((p) => p.section === s.id).map((p) => (
                <button
                  key={p.n}
                  type="button"
                  className={`thumb ${p.n - 1 === index ? 'is-current' : ''}`}
                  onClick={() => onPick(p.n - 1)}
                  style={{ '--i': p.n - s.start }}
                >
                  <img src={p.src} alt="" loading="lazy" />
                  <span><b>{String(p.n).padStart(2, '0')}</b> {p.title}</span>
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  )
}

function Zoom({ index, onChange, onClose }) {
  const p = PAGES[index]
  return (
    <div className="overlay zoom" role="dialog" aria-modal="true" aria-label={`Page ${p.n}`} onClick={onClose}>
      <button type="button" className="nav-arrow left" onClick={(e) => { e.stopPropagation(); onChange(Math.max(0, index - 1)) }} disabled={index === 0} aria-label="Previous page">
        <svg viewBox="0 0 24 24"><path d="M15 5 8 12l7 7" /></svg>
      </button>
      <figure className="zoom-page" onClick={(e) => e.stopPropagation()}>
        <img key={p.src} src={p.src} alt={`Page ${p.n}: ${p.title}`} />
        <figcaption>{String(p.n).padStart(2, '0')} · {p.title}</figcaption>
      </figure>
      <button type="button" className="nav-arrow right" onClick={(e) => { e.stopPropagation(); onChange(Math.min(TOTAL - 1, index + 1)) }} disabled={index === TOTAL - 1} aria-label="Next page">
        <svg viewBox="0 0 24 24"><path d="m9 5 7 7-7 7" /></svg>
      </button>
      <button type="button" className="icon-btn zoom-close" onClick={onClose} aria-label="Close">
        <svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18" /></svg>
      </button>
    </div>
  )
}
