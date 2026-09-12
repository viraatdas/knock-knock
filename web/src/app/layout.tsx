import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  weight: ["300", "400", "500"],
  display: "swap",
  variable: "--font-inter",
});

const siteUrl = "https://slide.viraat.dev";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Knock Knock - 5 Minute Dates: five-minute video dates, every night",
    template: "%s · Knock Knock - 5 Minute Dates",
  },
  description:
    "Every night from 7 to 8 PM Pacific, the doors open for five-minute video dates with people within 75 miles. Say keep talking or pass. A mutual yes unlocks a text chat. Sign in with your phone number, no profiles to scroll.",
  keywords: [
    "speed dating",
    "video dating",
    "dating app",
    "phone number signup",
    "singles",
    "Knock Knock - 5 Minute Dates",
  ],
  authors: [{ name: "Knock Knock - 5 Minute Dates" }],
  openGraph: {
    title: "Knock Knock - 5 Minute Dates: five-minute video dates, every night",
    description:
      "Doors open 7 to 8 PM Pacific. Five-minute video dates with people nearby. Keep talking or pass.",
    url: siteUrl,
    siteName: "Knock Knock - 5 Minute Dates",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Knock Knock - 5 Minute Dates: five-minute video dates, every night",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Knock Knock - 5 Minute Dates: five-minute video dates, every night",
    description:
      "Doors open 7 to 8 PM Pacific. Five-minute video dates with people nearby. Keep talking or pass.",
    images: ["/og.png"],
  },
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/icon.svg", type: "image/svg+xml" },
    ],
    apple: "/apple-touch-icon.png",
  },
};

export const viewport: Viewport = {
  themeColor: "#FAF6EF",
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
