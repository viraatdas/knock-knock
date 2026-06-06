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
    default: "Slide: video calling that feels fun again",
    template: "%s · Slide",
  },
  description:
    "Slide is the phone-number video calling app for iOS, Android, and the web. Sign in with your number, verify by code, and make video calling actually fun.",
  keywords: [
    "video calling",
    "fun video calling",
    "phone number signup",
    "group video",
    "screen share",
    "Slide app",
  ],
  authors: [{ name: "Slide" }],
  openGraph: {
    title: "Slide: video calling that feels fun again",
    description:
      "Phone-number video calls for iOS, Android, and the web.",
    url: siteUrl,
    siteName: "Slide",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Slide: video calling that feels fun again",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Slide: video calling that feels fun again",
    description:
      "Phone-number video calls for iOS, Android, and the web.",
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
