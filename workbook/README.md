# Memory Meter Workbook

Flip-through web version of the Group 6 workbook (Figma `Ritual` → page `workbook-export`, 32 A4 frames).

- Pages: `public/pages/01.webp … 32.webp`, exported from Figma at 2x (1588×2246) in reading order. Replace a file to update a page.
- Titles, sections and the contents-page links: `src/pages.js`.
- Page flip: [StPageFlip](https://github.com/Nodlik/StPageFlip) (`page-flip`).

```
npm install
npm run dev      # http://localhost:5173
npm run build    # static site in dist/
```

Deploy (static, Vercel): `npx vercel --prod` from this folder, or import the repo in Vercel with Root Directory `workbook`.

Controls: drag a page corner or click a page side · ← → / Space · Home / End · D one or two pages · G all pages · Z zoom · F fullscreen · `#/12` opens page 12.
