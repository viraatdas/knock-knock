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
    default: "Knock Knock: video calls you'll actually want to make",
    template: "%s · Knock Knock",
  },
  description:
    "Knock Knock is the open-source video calling app where you knock instead of ring: your taps travel in real time and nobody knows who's at the door until they answer. Phone-number signup, no ads, no tracking.",
  keywords: [
    "video calling",
    "fun video calling",
    "phone number signup",
    "group video",
    "screen share",
    "Knock Knock app",
  ],
  authors: [{ name: "Knock Knock" }],
  openGraph: {
    title: "Knock Knock: video calls you'll actually want to make",
    description:
      "Knock, don't ring. Open-source video calls with real-time taps.",
    url: siteUrl,
    siteName: "Knock Knock",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Knock Knock: video calls you'll actually want to make",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Knock Knock: video calls you'll actually want to make",
    description:
      "Knock, don't ring. Open-source video calls with real-time taps.",
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
