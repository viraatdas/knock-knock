# Slide design system — "quiet & precise"

The whole aesthetic is **white space + thin black type**. No gradients, no heavy
color, no decorative shadows. Identical across iOS, Android, and web.

## Color tokens

| Token | Hex | Use |
|---|---|---|
| `bg` | `#FFFFFF` | every background |
| `bgGrouped` | `#FAFAFA` | grouped sections |
| `text` | `#0A0A0A` | primary near-black text |
| `textSecondary` | `#6B7280` | secondary gray |
| `hairline` | `#ECECEC` | 1px borders & dividers |
| `accent` | `#0A0A0A` | primary action (call button), active toggles — pure black |
| `danger` | `#E5484D` | end call / decline / log out — the ONLY red |

## Typography

- System font: SF Pro (iOS) / Roboto (Android) / `-apple-system, Inter` (web).
- Weights: **Light (300)** large headings, **Regular (400)** body,
  **Medium (500)** only buttons / active states.
- Generous letter-spacing (~`0.02em`) on small uppercase labels.
- The "Slide" wordmark is always thin (300), tracking `+0.04em`.

## Shape & spacing

- 8px spacing grid. Touch targets ≥ 44px.
- Corner radius 12–16px, subtle. **1px hairlines instead of cards-with-shadows.**
- Generous padding; lots of white space.

## Motion

- Fast, subtle: 150–200ms ease-out.
- Incoming call: gentle pulse (scale 1.0→1.04), not flashy.

## Iconography

- Thin line icons, 1.5px stroke, to match the thin text.

## Navigation

- Bottom tab bar, 3 tabs: **Calls** (default) · **Contacts** · **Profile**.
- Active tab label only; thin line icons.
- Active calls take over full screen, modal above the tabs.
