import type { ReactNode } from "react";
import Nav from "./Nav";
import Footer from "./Footer";

export function LegalShell({
  title,
  updated,
  children,
}: {
  title: string;
  updated: string;
  children: ReactNode;
}) {
  return (
    <>
      <Nav />
      <main className="mx-auto max-w-2xl px-6 pb-24 pt-16 sm:pt-24">
        <h1 className="text-[40px] font-light leading-tight tracking-tight text-text sm:text-[52px]">
          {title}
        </h1>
        <p className="mt-3 text-[13px] font-light uppercase tracking-label text-text-secondary">
          Last updated {updated}
        </p>
        <div className="legal mt-12">{children}</div>
      </main>
      <Footer />
    </>
  );
}

export function Section({
  heading,
  children,
}: {
  heading: string;
  children: ReactNode;
}) {
  return (
    <section className="border-t border-hairline py-10 first:border-t-0 first:pt-0">
      <h2 className="text-[20px] font-normal leading-snug text-text">
        {heading}
      </h2>
      <div className="mt-3 space-y-4 text-[15px] font-light leading-relaxed text-text-secondary">
        {children}
      </div>
    </section>
  );
}
