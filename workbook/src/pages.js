// Figma "workbook-export" page (Ritual file) — one PNG per A4 frame, in reading order.
export const PAGE_W = 794
export const PAGE_H = 1123

const titles = [
  'Cover', 'Preface', 'Contents', 'Design brief',
  'Discover', 'Interviews', 'Drawing task and vignettes', 'What we found',
  'Define', 'Affinity diagram', 'Key tensions', 'Persona', 'POV and HMW',
  'Develop', 'Ideation', 'Sketches', 'From ideas to features', 'Lo-fi prototype',
  'Peer evaluation', 'Trying it out', 'What we changed',
  'Deliver', 'Hi-fi: how it works', 'Hi-fi: phone screen', 'Hi-fi: wall screen',
  'Hi-fi: projector setup', 'Hi-fi: controller', 'Building the hi-fi', 'User test',
  'Final concept', 'Takeaways', 'Back cover',
]

export const SECTIONS = [
  { id: 'intro', label: 'Intro', start: 1, end: 4 },
  { id: 'discover', label: 'Discover', start: 5, end: 8 },
  { id: 'define', label: 'Define', start: 9, end: 13 },
  { id: 'develop', label: 'Develop', start: 14, end: 21 },
  { id: 'deliver', label: 'Deliver', start: 22, end: 32 },
]

export const PAGES = titles.map((title, i) => {
  const n = i + 1
  return {
    n,
    title,
    src: `/pages/${String(n).padStart(2, '0')}.png`,
    section: SECTIONS.find((s) => n >= s.start && n <= s.end).id,
  }
})

// Contents page (03) hotspots, as % of the page box, measured from the Figma frame.
export const CONTENTS_LINKS = [
  { label: 'Design brief', page: 4, top: 26.5, height: 8.5 },
  { label: 'Discover phase', page: 5, top: 35.2, height: 12.5 },
  { label: 'Define phase', page: 9, top: 48.8, height: 14.6 },
  { label: 'Develop phase', page: 14, top: 64.8, height: 12.6 },
  { label: 'Deliver phase', page: 22, top: 78.2, height: 12.4 },
]
