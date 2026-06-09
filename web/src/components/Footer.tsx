import Link from "next/link";

export default function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="border-t border-hairline">
      <div className="mx-auto flex max-w-5xl flex-col gap-6 px-6 py-12 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-1">
          <Link
            href="/"
            className="text-lg font-light tracking-wordmark text-text"
          >
            Knock Knock
          </Link>
          <p className="text-[13px] font-light text-text-secondary">
            video calls you&apos;ll actually want to make
          </p>
        </div>

        <nav className="flex items-center gap-6 text-[13px] font-light text-text-secondary">
          <Link
            href="/privacy"
            className="transition-colors duration-150 ease-out hover:text-text"
          >
            Privacy
          </Link>
          <Link
            href="/terms"
            className="transition-colors duration-150 ease-out hover:text-text"
          >
            Terms
          </Link>
          <a
            href="https://github.com/viraatdas/knock-knock"
            className="transition-colors duration-150 ease-out hover:text-text"
          >
            GitHub
          </a>
          <span className="text-text-secondary/70">
            © {year} Knock Knock
          </span>
        </nav>
      </div>
    </footer>
  );
}
