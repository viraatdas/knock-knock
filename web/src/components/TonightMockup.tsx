export default function TonightMockup() {
  return (
    <div className="relative mx-auto w-[268px] select-none sm:w-[300px]">
      {/* Soft halo, very subtle, not a heavy shadow */}
      <div className="absolute inset-0 -z-10 translate-y-6 scale-95 rounded-[48px] bg-text/[0.04] blur-2xl" />

      {/* Device frame */}
      <div className="rounded-[42px] border border-hairline bg-bg p-2.5 shadow-[0_1px_0_rgba(42,33,27,0.05)]">
        <div className="relative overflow-hidden rounded-[34px] border border-hairline bg-bg">
          {/* notch */}
          <div className="absolute left-1/2 top-2 z-10 h-[22px] w-[88px] -translate-x-1/2 rounded-full bg-bg" />
          <div className="absolute left-1/2 top-[12px] z-20 h-1.5 w-10 -translate-x-1/2 rounded-full border border-hairline" />

          {/* screen */}
          <div className="flex flex-col items-center px-6 pb-8 pt-9 text-center">
            {/* status row */}
            <div className="flex w-full items-center justify-between text-[10px] font-light text-text-secondary">
              <span>9:41</span>
              <span className="tracking-label">tonight</span>
            </div>

            <p className="mt-10 text-[12px] font-light uppercase tracking-label text-text-secondary">
              Doors open in
            </p>
            <p className="mt-2 text-[38px] font-light leading-none tracking-tight text-text">
              2h 14m
            </p>
            <div className="mt-4 flex items-center gap-2">
              <span className="pulse-ring h-1.5 w-1.5 rounded-full bg-danger" />
              <p className="text-[12px] font-light text-text-secondary">
                Every day, 7 to 8 PM Pacific
              </p>
            </div>
          </div>

          {/* tab bar */}
          <div className="flex items-center justify-around border-t border-hairline px-6 py-3">
            <span className="text-[9px] font-medium text-text">Tonight</span>
            <span className="text-[9px] font-light text-text-secondary">
              Matches
            </span>
            <span className="text-[9px] font-light text-text-secondary">
              Profile
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
