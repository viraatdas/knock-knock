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
  LockIcon,
} from "@/components/icons";

const features = [
  {
    icon: VideoIcon,
    title: "Made for weak signal.",
    body: "Slide adapts in real time to whatever bandwidth you've got — gracefully scaling quality instead of freezing or dropping. One bar, packet loss, a crowded conference wifi: the call keeps going.",
  },
  {
    icon: WaveformIcon,
    title: "Audio survives anything.",
    body: "When the network really tanks, Slide protects the voice first — so even at your worst signal you can still hear each other clearly, no robot-stutter, no awkward 'you're cutting out.'",
  },
  {
    icon: PhoneIcon,
    title: "Your number is your account.",
    body: "No passwords, no emails, no usernames to forget. Sign in with the phone number you already have.",
  },
  {
    icon: PeopleIcon,
    title: "Bring everyone into the room.",
    body: "Group calls that stay smooth even when someone's on the subway. Tap a name, they slide in.",
  },
  {
    icon: ShareIcon,
    title: "Share your screen in a tap.",
    body: "Walk through a recipe, a slide, a bug. What you see, they see — instantly.",
  },
  {
    icon: LockIcon,
    title: "Private by default.",
    body: "Contacts are matched as hashed numbers. We never sell your data — there's nothing to sell.",
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
                <p className="text-[12px] font-light uppercase tracking-label text-text-secondary">
                  Built for bad internet
                </p>
              </Reveal>

              <Reveal delay={60}>
                <h1 className="mt-5 text-[64px] font-light leading-[0.95] tracking-wordmark text-text sm:text-[88px] lg:text-[104px]">
                  Slide
                </h1>
              </Reveal>

              <Reveal delay={120}>
                <p className="mt-6 max-w-md text-[22px] font-light leading-snug text-text sm:text-[26px]">
                  The video call that holds up on bad internet.
                </p>
              </Reveal>

              <Reveal delay={180}>
                <p className="mt-4 max-w-md text-[15px] font-light leading-relaxed text-text-secondary">
                  One bar, hotel wifi, a train tunnel — Slide keeps the call
                  alive while other apps freeze. Just your number. No passwords,
                  no feeds, no clutter.
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

        {/* Feature sections — hairline divided, generous whitespace */}
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
                Calls that don&apos;t drop
                <br className="hidden sm:block" /> when your signal does.
              </h2>
            </Reveal>
            <Reveal delay={80}>
              <p className="mx-auto mt-4 max-w-md text-[15px] font-light text-text-secondary">
                Slide is coming to iOS and Android. Be among the first.
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
