import { AppleIcon, PlayIcon } from "./icons";

function Badge({
  href,
  icon,
  line1,
  line2,
}: {
  href: string;
  icon: React.ReactNode;
  line1: string;
  line2: string;
}) {
  return (
    <a
      href={href}
      className="group inline-flex items-center gap-3 rounded-[14px] border border-hairline px-5 py-3 transition-colors duration-150 ease-out hover:border-text/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-text/15"
    >
      <span className="text-text/80">{icon}</span>
      <span className="flex flex-col leading-tight text-left">
        <span className="text-[11px] font-light tracking-label text-text-secondary">
          {line1}
        </span>
        <span className="text-[15px] font-normal text-text">{line2}</span>
      </span>
    </a>
  );
}

export default function StoreBadges() {
  return (
    <div className="flex flex-col gap-3 sm:flex-row">
      <Badge
        href="#"
        icon={<AppleIcon />}
        line1="Coming to the"
        line2="App Store"
      />
      <Badge
        href="#"
        icon={<PlayIcon />}
        line1="Coming to"
        line2="Google Play"
      />
    </div>
  );
}
