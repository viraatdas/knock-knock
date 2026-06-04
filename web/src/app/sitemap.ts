import type { MetadataRoute } from "next";

const base = "https://slide.viraat.dev";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return [
    { url: `${base}/`, lastModified: now, priority: 1 },
    { url: `${base}/web`, lastModified: now, priority: 0.9 },
    { url: `${base}/privacy`, lastModified: now, priority: 0.5 },
    { url: `${base}/terms`, lastModified: now, priority: 0.5 },
  ];
}
