import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        bg: "#FAF6EF",
        "bg-grouped": "#F2ECE1",
        text: "#2A211B",
        "text-secondary": "#8A7C6D",
        hairline: "#E6DCCB",
        accent: "#5A4632",
        danger: "#D4694F",
      },
      fontFamily: {
        sans: [
          "Inter",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "Roboto",
          "Helvetica Neue",
          "Arial",
          "sans-serif",
        ],
      },
      borderRadius: {
        DEFAULT: "12px",
        lg: "16px",
      },
      letterSpacing: {
        wordmark: "0.04em",
        label: "0.02em",
      },
      transitionTimingFunction: {
        "out-quiet": "cubic-bezier(0.16, 1, 0.3, 1)",
      },
      keyframes: {
        "reveal-up": {
          "0%": { opacity: "0", transform: "translateY(12px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "gentle-pulse": {
          "0%, 100%": { transform: "scale(1)" },
          "50%": { transform: "scale(1.04)" },
        },
      },
    },
  },
  plugins: [],
};

export default config;
