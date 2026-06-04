import type { Metadata } from "next";
import { LegalShell, Section } from "@/components/Legal";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How Slide collects, uses, and protects your information. Phone number as identity, hashed contact matching, and a commitment to never sell your data.",
};

export default function PrivacyPage() {
  return (
    <LegalShell title="Privacy Policy" updated="May 28, 2026">
      <Section heading="Overview">
        <p>
          Slide is a phone-only video calling app. We built it to be quiet,
          fast, and private. This policy explains what we collect, why, and the
          choices you have. We collect as little as we can while still letting
          you reach the people you care about.
        </p>
        <p>
          By using Slide, you agree to the practices described here. If you do
          not agree, please do not use the app.
        </p>
      </Section>

      <Section heading="Your phone number is your identity">
        <p>
          Slide uses your mobile phone number as your account identifier. There
          are no passwords, usernames, or email addresses required to sign in.
          When you register, we send a one-time verification code by SMS to
          confirm you control the number.
        </p>
        <p>
          We store your verified phone number, a unique account ID, and an
          optional display name and profile photo if you choose to add one.
        </p>
      </Section>

      <Section heading="Contacts and hashed matching">
        <p>
          To help you find friends already on Slide, the app can check your
          device contacts against our service. Before any phone number leaves
          your device, it is transformed into an irreversible cryptographic hash.
          We compare hashes, not raw numbers, so we never receive a readable copy
          of your address book.
        </p>
        <p>
          Hashes for numbers that are not Slide users are not retained in a form
          tied to you. You can decline contact access at any time and still use
          Slide by dialing numbers directly.
        </p>
      </Section>

      <Section heading="Calls and content">
        <p>
          Slide transmits your audio, video, and screen-share streams between
          participants to connect your calls. We do not record the contents of
          your calls, and we do not store your audio or video after a call ends.
        </p>
        <p>
          We keep limited call metadata, such as participants, start time, and
          duration, to show your recent calls list and to operate and
          troubleshoot the service. You can delete entries from your call history
          on your device.
        </p>
      </Section>

      <Section heading="Information we collect automatically">
        <p>
          To keep the service reliable and secure, we collect basic technical
          information such as device type, operating system version, app version,
          approximate region derived from your IP address, and diagnostic logs.
          We use this to fix crashes, prevent abuse, and improve call quality.
        </p>
      </Section>

      <Section heading="How we use information">
        <p>
          We use the information above to: verify your number and create your
          account; connect and route your calls; match you with contacts who use
          Slide; keep the service secure and prevent fraud or spam; and diagnose
          and improve performance.
        </p>
        <p>
          We do not use your information to build advertising profiles, and we do
          not show third-party ads in Slide.
        </p>
      </Section>

      <Section heading="We do not sell your data">
        <p>
          We do not sell, rent, or trade your personal information to anyone. We
          have no advertising business and no incentive to. The only parties who
          process data on our behalf are infrastructure providers (for example,
          SMS delivery, cloud hosting, and real-time media relays) that are bound
          by contract to use the data only to provide their service to us.
        </p>
      </Section>

      <Section heading="Data retention">
        <p>
          We keep your account information for as long as your account is active.
          Call metadata is retained for a limited period to operate the service
          and then deleted or aggregated. If you delete your account, we remove
          your profile and associated account data, except where we must retain
          limited records to comply with legal obligations.
        </p>
      </Section>

      <Section heading="Security">
        <p>
          Call media is encrypted in transit. We use industry-standard safeguards
          to protect account data at rest and in transit. No system is perfectly
          secure, but we work to limit what we collect so there is less to
          protect in the first place.
        </p>
      </Section>

      <Section heading="Your choices and rights">
        <p>
          You can edit or remove your display name and photo, revoke contact
          access in your device settings, and delete your account from within the
          app at any time. Depending on where you live, you may have additional
          rights to access, correct, or delete your personal information. To
          exercise them, contact us at the address below.
        </p>
      </Section>

      <Section heading="Children">
        <p>
          Slide is not directed to children under 13 (or the minimum age in your
          country), and we do not knowingly collect information from them.
        </p>
      </Section>

      <Section heading="Changes to this policy">
        <p>
          We may update this policy as the app evolves. When we make material
          changes, we will update the date at the top and, where appropriate,
          notify you in the app.
        </p>
      </Section>

      <Section heading="Contact">
        <p>
          Questions about privacy? Email us at{" "}
          <a
            href="mailto:privacy@slide.app"
            className="text-text underline decoration-hairline underline-offset-4 transition-colors duration-150 ease-out hover:decoration-text"
          >
            privacy@slide.app
          </a>
          .
        </p>
      </Section>
    </LegalShell>
  );
}
