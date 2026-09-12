import type { Metadata } from "next";
import { LegalShell, Section } from "@/components/Legal";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How Knock Knock - 5 Minute Dates collects, uses, and protects your information: your phone number, profile, coarse location, and messages between matches.",
};

export default function PrivacyPage() {
  return (
    <LegalShell title="Privacy Policy" updated="September 11, 2026">
      <Section heading="Overview">
        <p>
          Knock Knock - 5 Minute Dates is a phone-only video dating app. We collect
          as little as we can while still being able to match you with people
          nearby and let you talk to them. This policy explains what we
          collect, why, and the choices you have.
        </p>
        <p>
          You have to be 18 or older to use Knock Knock - 5 Minute Dates. By using
          the app, you agree to the practices described here. If you do not
          agree, please do not use the app.
        </p>
      </Section>

      <Section heading="Your phone number is your identity">
        <p>
          We use your mobile phone number as your account identifier. There
          are no usernames, passwords, or email addresses required to sign
          in. When you register, we verify a one-time code sent to your
          number to confirm you control it.
        </p>
      </Section>

      <Section heading="Your profile">
        <p>
          To set up a profile, we collect your name, birthday (so we can show
          your age and confirm you are 18 or older), gender, and who you want
          to be matched with. You can also add a short bio and a photo,
          which are optional.
        </p>
        <p>
          Your birthday itself is never shown to other users, only the age we
          calculate from it. Gender and who you want to see are used to find
          compatible matches and are shown on your profile the way you set
          them.
        </p>
      </Section>

      <Section heading="Location">
        <p>
          We use your location to find people within 75 miles of you.
          Before it is stored, your location is rounded to about a
          kilometer, so we keep a coarse location, not your exact address.
          Other users only ever see an approximate distance, such as
          &ldquo;12 miles away,&rdquo; never a location on a map.
        </p>
      </Section>

      <Section heading="Video dates">
        <p>
          Each date is a five-minute video call routed through our media
          infrastructure to connect you with the other person. We do not
          record video dates, and we do not store the audio or video after a
          date ends.
        </p>
      </Section>

      <Section heading="Matches and messages">
        <p>
          When you and someone else both choose to keep talking after a
          date, that is a match, and a text chat opens between you. Chat is
          text only: no photos or attachments. We store your messages so the
          chat works and so you can see your history, and we delete them if
          either person unmatches or deletes their account.
        </p>
      </Section>

      <Section heading="Reports and blocking">
        <p>
          If you block or report someone, we store who reported whom, the
          reason, and any details you provide, so we can review it and keep
          the app safe. Blocking someone ends any match between you and
          keeps you from being paired again.
        </p>
      </Section>

      <Section heading="Information we collect automatically">
        <p>
          To keep the service reliable and secure, we collect basic
          technical information such as device type, operating system
          version, app version, approximate region derived from your IP
          address, and diagnostic logs. We use this to fix crashes, prevent
          abuse, and keep dates connecting smoothly.
        </p>
      </Section>

      <Section heading="How we use information">
        <p>
          We use the information above to verify your number and create your
          account, match you with people nearby who fit your preferences,
          connect your video dates, deliver messages between matches, keep
          the service secure and respond to reports, and diagnose and
          improve the app.
        </p>
        <p>
          We do not use your information to build advertising profiles, and
          we do not show ads in Knock Knock - 5 Minute Dates.
        </p>
      </Section>

      <Section heading="We do not sell your data">
        <p>
          We do not sell, rent, or trade your personal information to
          anyone. We have no advertising business and no incentive to. The
          only parties who process data on our behalf are infrastructure
          providers, such as SMS delivery, cloud hosting, and video
          infrastructure, that are bound by contract to use the data only to
          provide their service to us.
        </p>
      </Section>

      <Section heading="Data retention">
        <p>
          We keep your account and profile information for as long as your
          account is active. You can delete your account from within the
          app at any time. Deleting your account removes your profile,
          photo, location, matches, and messages, except where we must
          retain limited records, such as open reports, to comply with legal
          obligations or keep the app safe.
        </p>
      </Section>

      <Section heading="Security">
        <p>
          Video and messages are encrypted in transit. We use
          industry-standard safeguards to protect account data at rest and
          in transit. No system is perfectly secure, but we work to limit
          what we collect so there is less to protect in the first place.
        </p>
      </Section>

      <Section heading="Your choices and rights">
        <p>
          You can edit your profile, bio, and photo, turn off location
          access in your device settings (Knock Knock - 5 Minute Dates will not be
          able to find you matches without it), and delete your account from
          within the app at any time. Depending on where you live, you may
          have additional rights to access, correct, or delete your
          personal information. To exercise them, contact us at the address
          below.
        </p>
      </Section>

      <Section heading="Age requirement">
        <p>
          Knock Knock - 5 Minute Dates is for adults. You must be 18 or older to
          create an account, and we ask for your birthday to confirm it. We
          do not knowingly collect information from anyone under 18, and we
          remove accounts we find are not eligible.
        </p>
      </Section>

      <Section heading="Changes to this policy">
        <p>
          We may update this policy as the app evolves. When we make
          material changes, we will update the date at the top and, where
          appropriate, notify you in the app.
        </p>
      </Section>

      <Section heading="Contact">
        <p>
          Questions about privacy? Email us at{" "}
          <a
            href="mailto:viraat@exla.ai"
            className="text-text underline decoration-hairline underline-offset-4 transition-colors duration-150 ease-out hover:decoration-text"
          >
            viraat@exla.ai
          </a>
          .
        </p>
      </Section>
    </LegalShell>
  );
}
