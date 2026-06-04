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
    default: "Slide: video calls built for bad internet",
    template: "%s · Slide",
  },
  description:
    "Slide is the video calling app built for bad internet. One bar, hotel wifi, a train tunnel: the call keeps going while other apps freeze. The clearest video calls with the people you know, on any device.",
  keywords: [
    "video calling",
    "bad internet video call",
    "low bandwidth video call",
    "phone number signup",
    "group video",
    "screen share",
    "Slide app",
  ],
  authors: [{ name: "Slide" }],
  openGraph: {
    title: "Slide: video calls built for bad internet",
    description:
      "The clearest video calls with the people you know. On any device.",
    url: siteUrl,
    siteName: "Slide",
    type: "website",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Slide: video calls built for bad internet",
    description:
      "The clearest video calls with the people you know. On any device.",
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
