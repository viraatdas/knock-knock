import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import Reveal from "@/components/Reveal";
import StoreBadges from "@/components/StoreBadges";
import PhoneMockup from "@/components/PhoneMockup";
import {
  PhoneIcon,
  VideoIcon,
  PeopleIcon,
  ShareIcon,
  WaveformIcon,
  CodeIcon,
} from "@/components/icons";

const features = [
  {
    icon: WaveformIcon,
    title: "Knock, don\u2019t ring.",
    body: "Tap, and their phone knocks \u2014 your actual rhythm, tap for tap, in real time. Keep knocking until they pick up. It feels like knuckles on wood, not a ringtone.",
  },
  {
    icon: VideoIcon,
    title: "Knock knock. Who\u2019s there?",
    body: "Knocks ring anonymously: no name, no photo, just a door. They answer by knocking back twice \u2014 and only then find out it\u2019s you. Answering a call hasn\u2019t felt like this before.",
  },
  {
    icon: PhoneIcon,
    title: "Your number is your account.",
    body: "No usernames, no passwords, no email. Sign in with your phone number, find the friends already on Knock Knock, and call them in two taps.",
  },
  {
    icon: PeopleIcon,
    title: "Bring everyone into the room.",
    body: "Group calls stay simple: pick the people you want and start the moment. No calendar invite, no link to hunt down.",
  },
  {
    icon: ShareIcon,
    title: "Made to feel good.",
    body: "Warm eggshell and espresso instead of clinical white. Haptics on every knock, a chime when your person arrives, a soft tock when the door closes.",
  },
  {
    icon: CodeIcon,
    title: "Open source.",
    body: "The whole app \u2014 iOS, backend, this site \u2014 is on GitHub. Read the code, audit how calls and contacts are handled, file issues, send PRs. Private by default, provable by design.",
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
                  alt="Knock Knock"
                  width={72}
                  height={72}
                  className="mb-6 h-16 w-16 rounded-2xl border border-hairline shadow-sm sm:h-[72px] sm:w-[72px]"
                />
              </Reveal>

              <Reveal delay={40}>
                <p className="text-[12px] font-light uppercase tracking-label text-text-secondary">
                  Don&apos;t ring. Knock.
                </p>
              </Reveal>

              <Reveal delay={60}>
                <h1 className="mt-5 text-[56px] font-light leading-[0.95] tracking-wordmark text-text sm:text-[76px] lg:text-[88px]">
                  Knock Knock
                </h1>
              </Reveal>

              <Reveal delay={120}>
                <p className="mt-6 max-w-md text-[22px] font-light leading-snug text-text sm:text-[26px]">
                  Video calls you&apos;ll actually want to make.
                </p>
              </Reveal>

              <Reveal delay={180}>
                <p className="mt-4 max-w-md text-[15px] font-light leading-relaxed text-text-secondary">
                  Tap, and their phone knocks with your rhythm. They knock back
                  twice to open the door. No feeds, no links, no ads — just
                  your people.
                </p>
              </Reveal>

              <Reveal delay={240}>
                <div id="get" className="mt-10 scroll-mt-24">
                  <StoreBadges />
                </div>
              </Reveal>
            </div>

            <Reveal delay={200} className="hidden lg:block">
              <PhoneMockup />
            </Reveal>
          </div>

          {/* Mobile mockup, below the fold of the text */}
          <Reveal delay={120} className="mt-16 lg:hidden">
            <PhoneMockup />
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
                Go knock on
                <br className="hidden sm:block" /> someone&apos;s door.
              </h2>
            </Reveal>
            <Reveal delay={80}>
              <p className="mx-auto mt-4 max-w-md text-[15px] font-light text-text-secondary">
                Free on the App Store today. Android is on the way.
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
