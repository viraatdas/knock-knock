import Link from "next/link";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

export default function NotFound() {
  return (
    <>
      <Nav />
      <main className="mx-auto flex min-h-[60vh] max-w-2xl flex-col items-center justify-center px-6 text-center">
        <p className="text-[12px] font-light uppercase tracking-label text-text-secondary">
          404
        </p>
        <h1 className="mt-4 text-[40px] font-light tracking-tight text-text sm:text-[52px]">
          Nothing here.
        </h1>
        <p className="mt-3 text-[15px] font-light text-text-secondary">
          The page you&rsquo;re looking for doesn&rsquo;t exist.
        </p>
        <Link
          href="/"
          className="mt-8 rounded-full border border-hairline px-5 py-2 text-[14px] font-medium text-text transition-colors duration-150 ease-out hover:border-text/30"
        >
          Back home
        </Link>
      </main>
      <Footer />
    </>
  );
}
