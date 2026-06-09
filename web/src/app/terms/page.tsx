import type { Metadata } from "next";
import { LegalShell, Section } from "@/components/Legal";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "The terms that govern your use of Knock Knock, the phone-only video calling app.",
};

export default function TermsPage() {
  return (
    <LegalShell title="Terms of Service" updated="May 28, 2026">
      <Section heading="Agreement">
        <p>
          These Terms of Service govern your access to and use of Knock Knock, a
          phone-only video calling app. By creating an account or using the app,
          you agree to these terms. If you do not agree, do not use Knock Knock.
        </p>
      </Section>

      <Section heading="Eligibility and your account">
        <p>
          You must be at least 13 years old (or the minimum age required in your
          country) to use Knock Knock. Your account is tied to your mobile phone
          number, which serves as your identity on the service. You are
          responsible for maintaining control of the number and the device used
          to access your account.
        </p>
        <p>
          If you change or give up your phone number, you should delete your
          Knock Knock account first, as the number may later be reassigned to someone
          else.
        </p>
      </Section>

      <Section heading="Acceptable use">
        <p>You agree not to use Knock Knock to:</p>
        <p>
          harass, threaten, or harm others; send spam or unsolicited calls;
          impersonate any person or entity; record participants without their
          consent where consent is required by law; violate any applicable law or
          the rights of others; or interfere with, disrupt, or attempt to gain
          unauthorized access to the service or its infrastructure.
        </p>
        <p>
          We may suspend or terminate accounts that violate these terms or that
          create risk for other users.
        </p>
      </Section>

      <Section heading="Your content">
        <p>
          Knock Knock transmits your live audio, video, and screen-share streams to the
          other participants in your call. We do not claim ownership of your call
          content. You are responsible for the content you share and for ensuring
          you have the right to share it.
        </p>
      </Section>

      <Section heading="Service availability">
        <p>
          We work hard to keep Knock Knock reliable, but the service is provided on an
          &ldquo;as is&rdquo; and &ldquo;as available&rdquo; basis. Call quality
          depends on factors outside our control, including your network and
          device. We may modify, suspend, or discontinue features at any time.
        </p>
      </Section>

      <Section heading="Privacy">
        <p>
          Your use of Knock Knock is also governed by our{" "}
          <a
            href="/privacy"
            className="text-text underline decoration-hairline underline-offset-4 transition-colors duration-150 ease-out hover:decoration-text"
          >
            Privacy Policy
          </a>
          , which explains how we handle your information, including your phone
          number and hashed contact matching.
        </p>
      </Section>

      <Section heading="Disclaimers and limitation of liability">
        <p>
          To the fullest extent permitted by law, Knock Knock and its providers
          disclaim all warranties, express or implied, including merchantability,
          fitness for a particular purpose, and non-infringement. We are not
          liable for any indirect, incidental, special, or consequential damages,
          or for any loss of data or profits arising from your use of the
          service.
        </p>
      </Section>

      <Section heading="Termination">
        <p>
          You may stop using Knock Knock and delete your account at any time from within
          the app. We may suspend or terminate your access if you violate these
          terms or if required to protect the service or other users.
        </p>
      </Section>

      <Section heading="Changes to these terms">
        <p>
          We may update these terms from time to time. When we make material
          changes, we will update the date above and, where appropriate, notify
          you in the app. Continued use of Knock Knock after changes take effect means
          you accept the updated terms.
        </p>
      </Section>

      <Section heading="Contact">
        <p>
          Questions about these terms? Email us at{" "}
          <a
            href="mailto:hello@slide.app"
            className="text-text underline decoration-hairline underline-offset-4 transition-colors duration-150 ease-out hover:decoration-text"
          >
            hello@slide.app
          </a>
          .
        </p>
      </Section>
    </LegalShell>
  );
}
