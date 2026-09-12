import type { Metadata } from "next";
import { LegalShell, Section } from "@/components/Legal";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "The terms that govern your use of Knock Knock - 5 Minute Dates, the phone-only video dating app.",
};

export default function TermsPage() {
  return (
    <LegalShell title="Terms of Service" updated="September 11, 2026">
      <Section heading="Agreement">
        <p>
          These Terms of Service govern your access to and use of Knock
          Knock - 5 Minute Dates, a phone-only video dating app. By creating an
          account or using the app, you agree to these terms. If you do not
          agree, do not use Knock Knock - 5 Minute Dates.
        </p>
      </Section>

      <Section heading="Eligibility and your account">
        <p>
          You must be at least 18 years old to use Knock Knock - 5 Minute Dates.
          Your account is tied to your mobile phone number, which serves as
          your identity on the service. You are responsible for maintaining
          control of the number and the device used to access your account.
        </p>
        <p>
          If you change or give up your phone number, you should delete
          your account first, as the number may later be reassigned to
          someone else.
        </p>
      </Section>

      <Section heading="How dates work">
        <p>
          Each night from 7 to 8 PM Pacific, you can join the lobby and be
          matched for a five-minute video date with someone within 75 miles
          who fits your preferences. After the date, you and the other
          person privately choose to keep talking or pass. A match, and a
          text chat, only happens when you both say keep talking.
        </p>
        <p>
          We do not record video dates. You may not record, screenshot, or
          otherwise capture another participant without their consent,
          where consent is required by law.
        </p>
      </Section>

      <Section heading="Acceptable use">
        <p>You agree not to use Knock Knock - 5 Minute Dates to:</p>
        <p>
          harass, threaten, or harm others; misrepresent your age, identity,
          or intentions; send spam or solicit money, services, or business;
          record or share another participant&rsquo;s video or messages
          without consent where consent is required by law; violate any
          applicable law or the rights of others; or interfere with,
          disrupt, or attempt to gain unauthorized access to the service or
          its infrastructure.
        </p>
        <p>
          You can report or block anyone from within the app. We may
          suspend or terminate accounts that violate these terms or that
          create risk for other users.
        </p>
      </Section>

      <Section heading="Your content">
        <p>
          Knock Knock - 5 Minute Dates transmits your live video during dates and
          your messages with matches. We do not claim ownership of your
          video or messages. You are responsible for what you say and share
          and for treating the people you meet with respect.
        </p>
      </Section>

      <Section heading="Service availability">
        <p>
          We work hard to keep Knock Knock - 5 Minute Dates reliable, but the
          service is provided on an &ldquo;as is&rdquo; and &ldquo;as
          available&rdquo; basis. Being matched depends on how many people
          are in the lobby at the same time, and call quality depends on
          factors outside our control, including your network and device.
          We may modify, suspend, or discontinue features at any time.
        </p>
      </Section>

      <Section heading="Privacy">
        <p>
          Your use of Knock Knock - 5 Minute Dates is also governed by our{" "}
          <a
            href="/privacy"
            className="text-text underline decoration-hairline underline-offset-4 transition-colors duration-150 ease-out hover:decoration-text"
          >
            Privacy Policy
          </a>
          , which explains how we handle your information, including your
          phone number, profile, and coarse location.
        </p>
      </Section>

      <Section heading="Disclaimers and limitation of liability">
        <p>
          To the fullest extent permitted by law, Knock Knock - 5 Minute Dates and
          its providers disclaim all warranties, express or implied,
          including merchantability, fitness for a particular purpose, and
          non-infringement. We are not liable for any indirect, incidental,
          special, or consequential damages, or for any loss of data or
          profits arising from your use of the service, and we are not
          responsible for the conduct of other users, on or off the app.
        </p>
      </Section>

      <Section heading="Termination">
        <p>
          You may stop using Knock Knock - 5 Minute Dates and delete your account
          at any time from within the app. We may suspend or terminate your
          access if you violate these terms, misrepresent your age, or if
          required to protect the service or other users.
        </p>
      </Section>

      <Section heading="Changes to these terms">
        <p>
          We may update these terms from time to time. When we make
          material changes, we will update the date above and, where
          appropriate, notify you in the app. Continued use of Knock Knock - 5 Minute Dates after changes take effect means you accept the updated
          terms.
        </p>
      </Section>

      <Section heading="Contact">
        <p>
          Questions about these terms? Email us at{" "}
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
