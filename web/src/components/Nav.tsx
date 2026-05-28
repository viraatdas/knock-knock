import Link from "next/link";

export default function Nav() {
  return (
    <header className="sticky top-0 z-40 border-b border-hairline bg-white/80 backdrop-blur-md">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
        <Link
          href="/"
          className="text-[17px] font-light tracking-wordmark text-text transition-opacity duration-150 ease-out hover:opacity-70"
        >
          Slide
        </Link>
        <a
          href="#get"
          className="rounded-full border border-hairline px-4 py-1.5 text-[13px] font-medium text-text transition-colors duration-150 ease-out hover:border-text/30"
        >
          Get the app
        </a>
      </div>
    </header>
  );
}
