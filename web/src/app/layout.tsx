import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  weight: ["300", "400", "500"],
  display: "swap",
  variable: "--font-inter",
});

const siteUrl = "https://web-viraatdas-projects.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Slide — does one thing well",
    template: "%s — Slide",
  },
  description:
    "Slide does one thing well: video calls. Nothing else. Sign up with your phone number — no passwords, no feeds, no clutter. Clear 1:1 and group video with screen share.",
  keywords: [
    "video calling",
    "phone number signup",
    "group video",
    "screen share",
    "Slide app",
  ],
  authors: [{ name: "Slide" }],
  openGraph: {
    title: "Slide — the cleanest way to call",
    description:
      "A phone-only video calling app for the friends who never call. No passwords. Just clear video.",
    url: siteUrl,
    siteName: "Slide",
    type: "website",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Slide — the cleanest way to call",
    description:
      "A phone-only video calling app for the friends who never call.",
  },
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/icon.svg", type: "image/svg+xml" },
    ],
    apple: "/icon.svg",
  },
};

export const viewport: Viewport = {
  themeColor: "#FFFFFF",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="bg-bg font-sans text-text antialiased">{children}</body>
    </html>
  );
}
