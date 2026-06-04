import { PhoneIcon, PeopleIcon } from "./icons";

function CallRow({
  initials,
  name,
  meta,
  missed = false,
}: {
  initials: string;
  name: string;
  meta: string;
  missed?: boolean;
}) {
  return (
    <div className="flex items-center gap-3 py-3">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-hairline text-[12px] font-light text-text-secondary">
        {initials}
      </div>
      <div className="min-w-0 flex-1">
        <div
          className={`truncate text-[14px] font-normal ${
            missed ? "text-danger" : "text-text"
          }`}
        >
          {name}
        </div>
        <div className="flex items-center gap-1.5 text-[11px] font-light text-text-secondary">
          <span className="text-[10px]">↗</span>
          {meta}
        </div>
      </div>
      <PhoneIcon className="h-[18px] w-[18px] text-text/70" />
    </div>
  );
}

export default function PhoneMockup() {
  return (
    <div className="relative mx-auto w-[268px] select-none sm:w-[300px]">
      {/* Soft halo, very subtle, not a heavy shadow */}
      <div className="absolute inset-0 -z-10 translate-y-6 scale-95 rounded-[48px] bg-text/[0.03] blur-2xl" />

      {/* Device frame */}
      <div className="rounded-[42px] border border-hairline bg-white p-2.5 shadow-[0_1px_0_rgba(10,10,10,0.04)]">
        <div className="relative overflow-hidden rounded-[34px] border border-hairline bg-white">
          {/* notch */}
          <div className="absolute left-1/2 top-2 z-10 h-[22px] w-[88px] -translate-x-1/2 rounded-full bg-white" />
          <div className="absolute left-1/2 top-[12px] z-20 h-1.5 w-10 -translate-x-1/2 rounded-full border border-hairline" />

          {/* screen */}
          <div className="px-5 pb-5 pt-9">
            {/* status row */}
            <div className="flex items-center justify-between text-[10px] font-light text-text-secondary">
              <span>9:41</span>
              <span className="tracking-label">slide</span>
            </div>

            {/* header */}
            <div className="mt-5 flex items-baseline justify-between">
              <h3 className="text-[22px] font-light tracking-tight text-text">
                Calls
              </h3>
              <span className="text-[11px] font-light text-text-secondary">
                Edit
              </span>
            </div>

            {/* list */}
            <div className="mt-2 divide-y divide-hairline">
              <CallRow initials="MR" name="Maya Reyes" meta="Today, 8:24 PM" />
              <CallRow
                initials="JK"
                name="Jordan Kim"
                meta="Missed · 3:10 PM"
                missed
              />
              <CallRow initials="AW" name="Alex Whitman" meta="Yesterday" />
              <CallRow initials="SP" name="Sam Patel" meta="Mon" />
            </div>
          </div>

          {/* tab bar */}
          <div className="flex items-center justify-around border-t border-hairline px-6 py-3">
            <div className="flex flex-col items-center gap-1">
              <PhoneIcon className="h-[18px] w-[18px] text-text" />
              <span className="text-[9px] font-medium text-text">Calls</span>
            </div>
            <PeopleIcon className="h-[18px] w-[18px] text-text-secondary" />
            <div className="flex h-[18px] w-[18px] items-center justify-center">
              <div className="h-4 w-4 rounded-full border border-text-secondary" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
