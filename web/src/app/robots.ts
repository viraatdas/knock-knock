import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: "https://web-viraatdas-projects.vercel.app/sitemap.xml",
  };
}
