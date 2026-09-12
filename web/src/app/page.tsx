import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import Reveal from "@/components/Reveal";
import StoreBadges from "@/components/StoreBadges";
import TonightMockup from "@/components/TonightMockup";
import {
  WaveformIcon,
  VideoIcon,
  PeopleIcon,
  ChatIcon,
  LocationIcon,
  PhoneIcon,
  CodeIcon,
} from "@/components/icons";

const features = [
  {
    icon: WaveformIcon,
    title: "The doors open at 7.",
    body: "Every night, 7 to 8 PM Pacific, the lobby opens near you. Show up any time in that hour and you're in for the night.",
  },
  {
    icon: VideoIcon,
    title: "Five minutes. That's the whole date.",
    body: "Video dates run exactly five minutes. Long enough to know if you want to talk again, short enough that it never drags.",
  },
  {
    icon: PeopleIcon,
    title: "Keep talking, or pass.",
    body: "After the date, you both quietly say keep talking or pass. Only a mutual yes turns into a match. A pass is never shown to the other person.",
  },
  {
    icon: ChatIcon,
    title: "A real chat once you match.",
    body: "Matching unlocks a plain text chat. No photos, no attachments, just messages back and forth.",
  },
  {
    icon: LocationIcon,
    title: "People within 75 miles.",
    body: "Matches are close enough to actually meet up. We use a rough location, never your exact address.",
  },
  {
    icon: PhoneIcon,
    title: "Just your phone number.",
    body: "No usernames, no passwords. Sign in with your number, fill out a quick profile, and you're ready for tonight's lobby.",
  },
  {
    icon: CodeIcon,
    title: "Open source.",
    body: "The whole app, iOS, backend, this site, is on GitHub. Read the code, see how dates and matches are handled, file issues, send PRs.",
    href: "https://github.com/viraatdas/knock-knock",
    linkLabel: "github.com/viraatdas/knock-knock",
  },
];

export default function Home() {
  return (
    <>
      <Nav />

      <main>
        {/* Hero */}
        <section className="mx-auto max-w-5xl px-6 pb-24 pt-20 sm:pt-28 lg:pt-36">
          <div className="grid items-center gap-16 lg:grid-cols-[1.1fr_0.9fr]">
            <div>
              <Reveal>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/slide-logo.svg"
                  alt="Knock Knock - 5 Minute Dates"
                  width={72}
                  height={72}
                  className="mb-6 h-16 w-16 rounded-2xl border border-hairline shadow-sm sm:h-[72px] sm:w-[72px]"
                />
              </Reveal>

              <Reveal delay={60}>
                <h1 className="mt-5 text-[56px] font-light leading-[0.95] tracking-wordmark text-text sm:text-[76px] lg:text-[88px]">
                  Knock Knock
                </h1>
              </Reveal>

              <Reveal delay={120}>
                <p className="mt-6 max-w-md text-[22px] font-light leading-snug text-text sm:text-[26px]">
                  Five-minute video dates. Every night, 7 to 8 PM Pacific.
                </p>
              </Reveal>

              <Reveal delay={180}>
                <p className="mt-4 max-w-md text-[15px] font-light leading-relaxed text-text-secondary">
                  Every night the doors open near you for five-minute video
                  dates with people within 75 miles. After each one, you both
                  say keep talking or pass. A mutual yes unlocks a text chat.
                </p>
              </Reveal>

              <Reveal delay={240}>
                <div id="get" className="mt-10 scroll-mt-24">
                  <StoreBadges />
                </div>
              </Reveal>
            </div>

            <Reveal delay={200} className="hidden lg:block">
              <TonightMockup />
            </Reveal>
          </div>

          {/* Mobile mockup, below the fold of the text */}
          <Reveal delay={120} className="mt-16 lg:hidden">
            <TonightMockup />
          </Reveal>
        </section>

        {/* Feature sections: hairline divided, generous whitespace */}
        <section className="border-t border-hairline">
          <div className="mx-auto max-w-5xl px-6">
            {features.map((f, i) => {
              const Icon = f.icon;
              return (
                <Reveal
                  key={f.title}
                  as="article"
                  delay={i % 2 === 0 ? 0 : 60}
                  className={`grid gap-6 py-20 sm:grid-cols-[auto_1fr] sm:gap-12 ${
                    i !== 0 ? "border-t border-hairline" : ""
                  }`}
                >
                  <div className="text-text/80">
                    <Icon className="h-7 w-7" />
                  </div>
                  <div className="max-w-xl">
                    <h2 className="text-[28px] font-light leading-tight tracking-tight text-text sm:text-[34px]">
                      {f.title}
                    </h2>
                    <p className="mt-3 text-[16px] font-light leading-relaxed text-text-secondary">
                      {f.body}
                    </p>
                    {"href" in f && f.href ? (
                      <a
                        href={f.href}
                        className="mt-4 inline-block text-[14px] font-normal text-accent underline decoration-hairline underline-offset-4 transition-colors duration-150 ease-out hover:decoration-accent"
                      >
                        {f.linkLabel}
                      </a>
                    ) : null}
                  </div>
                </Reveal>
              );
            })}
          </div>
        </section>

        {/* Closing CTA */}
        <section className="border-t border-hairline">
          <div className="mx-auto max-w-5xl px-6 py-28 text-center">
            <Reveal>
              <h2 className="mx-auto max-w-2xl text-[36px] font-light leading-tight tracking-tight text-text sm:text-[48px]">
                The doors open
                <br className="hidden sm:block" /> at 7 tonight.
              </h2>
            </Reveal>
            <Reveal delay={80}>
              <p className="mx-auto mt-4 max-w-md text-[15px] font-light text-text-secondary">
                Free on the App Store. You have to be 18 or older to join.
              </p>
            </Reveal>
            <Reveal delay={140}>
              <div className="mt-10 flex justify-center">
                <StoreBadges />
              </div>
            </Reveal>
          </div>
        </section>
      </main>

      <Footer />
    </>
  );
}
