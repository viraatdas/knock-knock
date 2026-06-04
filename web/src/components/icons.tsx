import type { SVGProps } from "react";

const base = {
  width: 28,
  height: 28,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.5,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

export function PhoneIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <path d="M6.5 3.5h2l1.2 3.2-1.6 1.2a11 11 0 0 0 4.8 4.8l1.2-1.6 3.2 1.2v2a2 2 0 0 1-2.2 2A14.5 14.5 0 0 1 4.5 5.7 2 2 0 0 1 6.5 3.5Z" />
    </svg>
  );
}

export function VideoIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <rect x="3" y="6.5" width="12" height="11" rx="2.5" />
      <path d="M15 10.2 21 7v10l-6-3.2" />
    </svg>
  );
}

export function PeopleIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <circle cx="9" cy="8" r="3" />
      <path d="M3.5 19a5.5 5.5 0 0 1 11 0" />
      <path d="M16 5.2a3 3 0 0 1 0 5.6" />
      <path d="M17.5 13.4A5.5 5.5 0 0 1 20.5 18" />
    </svg>
  );
}

export function ShareIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <rect x="3" y="4.5" width="18" height="12" rx="2" />
      <path d="M8 20h8M12 16.5V20" />
      <path d="M12 13V8M12 8l-2.2 2.2M12 8l2.2 2.2" />
    </svg>
  );
}

export function WebIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <rect x="3" y="5" width="18" height="12" rx="2" />
      <path d="M8 20h8M12 17v3" />
    </svg>
  );
}

export function WaveformIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <path d="M4 12h2M9 7v10M14 4v16M19 9v6" />
    </svg>
  );
}

export function LockIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <rect x="5" y="10.5" width="14" height="9.5" rx="2.5" />
      <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
      <path d="M12 14.5v2.5" />
    </svg>
  );
}

export function CodeIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...base} {...props} aria-hidden="true">
      <path d="M8.5 8.5 4 12l4.5 3.5" />
      <path d="M15.5 8.5 20 12l-4.5 3.5" />
      <path d="M13 6l-2 12" />
    </svg>
  );
}

export function AppleIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg
      width={18}
      height={18}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
      {...props}
    >
      <path d="M16.36 12.78c.02 2.4 2.1 3.2 2.13 3.21-.02.06-.33 1.14-1.1 2.26-.66.97-1.35 1.93-2.43 1.95-1.06.02-1.4-.63-2.62-.63-1.21 0-1.59.61-2.59.65-1.04.04-1.84-1.05-2.51-2.01-1.36-1.97-2.4-5.57-1-8 .69-1.2 1.93-1.96 3.27-1.98 1.02-.02 1.99.69 2.62.69.62 0 1.8-.85 3.03-.73.52.02 1.97.21 2.9 1.58-.07.05-1.73 1.01-1.71 3.01M14.4 6.4c.55-.67.92-1.6.82-2.53-.79.03-1.75.53-2.32 1.2-.51.59-.96 1.53-.84 2.43.88.07 1.78-.45 2.34-1.1" />
    </svg>
  );
}

export function PlayIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg
      width={18}
      height={18}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
      {...props}
    >
      <path d="M4.4 3.3c-.24.16-.4.45-.4.85v15.7c0 .4.16.69.4.85l8.46-8.7L4.4 3.3Z" />
      <path d="m14.06 9.7 2.9 1.66c.9.51.9 1.77 0 2.28l-2.9 1.66-2.3-2.36 2.3-2.24-.0-.0Z" opacity=".55" />
      <path d="M13.4 12.9 5.2 21.3c.27.13.6.11.95-.09l9.7-5.56-2.45-2.75Z" opacity=".8" />
      <path d="m16.17 7.83-9.99-5.7c-.36-.2-.7-.22-.97-.08l8.2 8.41 2.76-2.63Z" opacity=".7" />
    </svg>
  );
}
