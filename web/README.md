# Knock Knock - 5 Minute Dates web

The marketing site for **Knock Knock - 5 Minute Dates**, a phone-only video
speed-dating app. Every night from 7 to 8 PM Pacific, the doors open for
five-minute video dates with people nearby.

**Live:** https://slide.viraat.dev

Built with **Next.js (App Router, TypeScript)** + **Tailwind CSS**, following
the warm design system in [`../AGENTS.md`](../AGENTS.md): eggshell
backgrounds, espresso type, hairline dividers, generous whitespace, and
fast/subtle motion that respects `prefers-reduced-motion`.

## Pages

| Route      | Description                                              |
| ---------- | --------------------------------------------------------- |
| `/`        | Marketing site: hero, tonight mockup, feature list, App Store badge. |
| `/privacy` | Privacy Policy.                                            |
| `/terms`   | Terms of Service.                                          |

Also generates `/robots.txt` and `/sitemap.xml`.

## Local development

```bash
cd web
npm install
npm run dev      # http://localhost:3000
```

## Production build

```bash
npm run build    # type-checks + builds; must succeed with zero errors
npm run start    # serve the production build locally
```

## Deploy (Vercel)

The project is linked to the Vercel project `viraatdas-projects/web`.

```bash
vercel --yes            # preview deploy
vercel --prod --yes     # production deploy
```

> After changing the canonical domain, update `siteUrl` in
> `src/app/layout.tsx` and the `base` URLs in `src/app/sitemap.ts` /
> `src/app/robots.ts` so Open Graph tags, the sitemap, and robots.txt point at
> the live host.

## Project structure

```
web/
├── src/
│   ├── app/
│   │   ├── layout.tsx        # metadata, Open Graph, fonts, favicon
│   │   ├── page.tsx          # marketing homepage
│   │   ├── globals.css       # tokens + scroll-reveal + reduced-motion
│   │   ├── not-found.tsx     # 404
│   │   ├── robots.ts
│   │   ├── sitemap.ts
│   │   ├── privacy/page.tsx
│   │   └── terms/page.tsx
│   └── components/
│       ├── Nav.tsx
│       ├── Footer.tsx
│       ├── Reveal.tsx        # IntersectionObserver scroll-reveal
│       ├── StoreBadges.tsx   # App Store badge pill
│       ├── TonightMockup.tsx # CSS device frame of the Tonight screen
│       ├── Legal.tsx         # shared shell for /privacy and /terms
│       └── icons.tsx         # 1.5px thin-line icons
├── public/
│   ├── favicon.svg
│   └── icon.svg
├── tailwind.config.ts        # design tokens
└── ...
```
