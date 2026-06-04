import type { Metadata } from "next";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import SlideWebApp from "@/components/SlideWebApp";

export const metadata: Metadata = {
  title: "Slide Web",
  description:
    "Use Slide from the browser. Sign in with your phone number, verify by code, and call people by phone number.",
};

export default function WebPage() {
  return (
    <>
      <Nav />
      <main>
        <SlideWebApp />
      </main>
      <Footer />
    </>
  );
}
