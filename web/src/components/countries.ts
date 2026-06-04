// Country dial codes for the phone signup selector.
// dial is the calling code without the leading "+".

export type Country = { name: string; iso2: string; dial: string };

export const COUNTRIES: Country[] = [
  { name: "Afghanistan", iso2: "AF", dial: "93" },
  { name: "Albania", iso2: "AL", dial: "355" },
  { name: "Algeria", iso2: "DZ", dial: "213" },
  { name: "Argentina", iso2: "AR", dial: "54" },
  { name: "Australia", iso2: "AU", dial: "61" },
  { name: "Austria", iso2: "AT", dial: "43" },
  { name: "Bangladesh", iso2: "BD", dial: "880" },
  { name: "Belgium", iso2: "BE", dial: "32" },
  { name: "Bolivia", iso2: "BO", dial: "591" },
  { name: "Brazil", iso2: "BR", dial: "55" },
  { name: "Bulgaria", iso2: "BG", dial: "359" },
  { name: "Cambodia", iso2: "KH", dial: "855" },
  { name: "Cameroon", iso2: "CM", dial: "237" },
  { name: "Canada", iso2: "CA", dial: "1" },
  { name: "Chile", iso2: "CL", dial: "56" },
  { name: "China", iso2: "CN", dial: "86" },
  { name: "Colombia", iso2: "CO", dial: "57" },
  { name: "Costa Rica", iso2: "CR", dial: "506" },
  { name: "Croatia", iso2: "HR", dial: "385" },
  { name: "Czechia", iso2: "CZ", dial: "420" },
  { name: "Denmark", iso2: "DK", dial: "45" },
  { name: "Dominican Republic", iso2: "DO", dial: "1" },
  { name: "Ecuador", iso2: "EC", dial: "593" },
  { name: "Egypt", iso2: "EG", dial: "20" },
  { name: "El Salvador", iso2: "SV", dial: "503" },
  { name: "Estonia", iso2: "EE", dial: "372" },
  { name: "Ethiopia", iso2: "ET", dial: "251" },
  { name: "Finland", iso2: "FI", dial: "358" },
  { name: "France", iso2: "FR", dial: "33" },
  { name: "Georgia", iso2: "GE", dial: "995" },
  { name: "Germany", iso2: "DE", dial: "49" },
  { name: "Ghana", iso2: "GH", dial: "233" },
  { name: "Greece", iso2: "GR", dial: "30" },
  { name: "Guatemala", iso2: "GT", dial: "502" },
  { name: "Honduras", iso2: "HN", dial: "504" },
  { name: "Hong Kong", iso2: "HK", dial: "852" },
  { name: "Hungary", iso2: "HU", dial: "36" },
  { name: "Iceland", iso2: "IS", dial: "354" },
  { name: "India", iso2: "IN", dial: "91" },
  { name: "Indonesia", iso2: "ID", dial: "62" },
  { name: "Iran", iso2: "IR", dial: "98" },
  { name: "Iraq", iso2: "IQ", dial: "964" },
  { name: "Ireland", iso2: "IE", dial: "353" },
  { name: "Israel", iso2: "IL", dial: "972" },
  { name: "Italy", iso2: "IT", dial: "39" },
  { name: "Jamaica", iso2: "JM", dial: "1" },
  { name: "Japan", iso2: "JP", dial: "81" },
  { name: "Jordan", iso2: "JO", dial: "962" },
  { name: "Kazakhstan", iso2: "KZ", dial: "7" },
  { name: "Kenya", iso2: "KE", dial: "254" },
  { name: "Kuwait", iso2: "KW", dial: "965" },
  { name: "Latvia", iso2: "LV", dial: "371" },
  { name: "Lebanon", iso2: "LB", dial: "961" },
  { name: "Lithuania", iso2: "LT", dial: "370" },
  { name: "Luxembourg", iso2: "LU", dial: "352" },
  { name: "Malaysia", iso2: "MY", dial: "60" },
  { name: "Mexico", iso2: "MX", dial: "52" },
  { name: "Morocco", iso2: "MA", dial: "212" },
  { name: "Nepal", iso2: "NP", dial: "977" },
  { name: "Netherlands", iso2: "NL", dial: "31" },
  { name: "New Zealand", iso2: "NZ", dial: "64" },
  { name: "Nigeria", iso2: "NG", dial: "234" },
  { name: "Norway", iso2: "NO", dial: "47" },
  { name: "Oman", iso2: "OM", dial: "968" },
  { name: "Pakistan", iso2: "PK", dial: "92" },
  { name: "Panama", iso2: "PA", dial: "507" },
  { name: "Paraguay", iso2: "PY", dial: "595" },
  { name: "Peru", iso2: "PE", dial: "51" },
  { name: "Philippines", iso2: "PH", dial: "63" },
  { name: "Poland", iso2: "PL", dial: "48" },
  { name: "Portugal", iso2: "PT", dial: "351" },
  { name: "Qatar", iso2: "QA", dial: "974" },
  { name: "Romania", iso2: "RO", dial: "40" },
  { name: "Russia", iso2: "RU", dial: "7" },
  { name: "Saudi Arabia", iso2: "SA", dial: "966" },
  { name: "Serbia", iso2: "RS", dial: "381" },
  { name: "Singapore", iso2: "SG", dial: "65" },
  { name: "Slovakia", iso2: "SK", dial: "421" },
  { name: "Slovenia", iso2: "SI", dial: "386" },
  { name: "South Africa", iso2: "ZA", dial: "27" },
  { name: "South Korea", iso2: "KR", dial: "82" },
  { name: "Spain", iso2: "ES", dial: "34" },
  { name: "Sri Lanka", iso2: "LK", dial: "94" },
  { name: "Sweden", iso2: "SE", dial: "46" },
  { name: "Switzerland", iso2: "CH", dial: "41" },
  { name: "Taiwan", iso2: "TW", dial: "886" },
  { name: "Tanzania", iso2: "TZ", dial: "255" },
  { name: "Thailand", iso2: "TH", dial: "66" },
  { name: "Tunisia", iso2: "TN", dial: "216" },
  { name: "Turkey", iso2: "TR", dial: "90" },
  { name: "Uganda", iso2: "UG", dial: "256" },
  { name: "Ukraine", iso2: "UA", dial: "380" },
  { name: "United Arab Emirates", iso2: "AE", dial: "971" },
  { name: "United Kingdom", iso2: "GB", dial: "44" },
  { name: "United States", iso2: "US", dial: "1" },
  { name: "Uruguay", iso2: "UY", dial: "598" },
  { name: "Venezuela", iso2: "VE", dial: "58" },
  { name: "Vietnam", iso2: "VN", dial: "84" },
  { name: "Zambia", iso2: "ZM", dial: "260" },
  { name: "Zimbabwe", iso2: "ZW", dial: "263" },
];

export const DEFAULT_COUNTRY: Country =
  COUNTRIES.find((c) => c.iso2 === "US") ?? COUNTRIES[0];

// 🇺🇸 from "US" via regional-indicator code points.
export function flagEmoji(iso2: string): string {
  return iso2
    .toUpperCase()
    .replace(/./g, (c) => String.fromCodePoint(127397 + c.charCodeAt(0)));
}

// Max national digits we keep for a country (NANP is exactly 10).
export function maxNationalDigits(country: Country): number {
  return country.dial === "1" ? 10 : 15;
}

// Pretty as-you-type grouping of the NATIONAL number (no country code).
// NANP (dial 1) → "415 555 0123" (3-3-4); everything else → groups of 3.
export function formatNational(digits: string, country: Country): string {
  const d = digits.replace(/\D/g, "").slice(0, maxNationalDigits(country));
  if (!d) return "";
  if (country.dial === "1") {
    return [d.slice(0, 3), d.slice(3, 6), d.slice(6, 10)].filter(Boolean).join(" ");
  }
  return (d.match(/.{1,3}/g) ?? []).join(" ");
}

// Best-effort default from the browser locale's region (e.g. "en-GB" -> GB).
export function detectCountry(): Country {
  try {
    const loc =
      (typeof navigator !== "undefined" && navigator.language) || "";
    const m = loc.match(/[-_]([A-Za-z]{2})\b/);
    if (m) {
      const region = m[1].toUpperCase();
      const hit = COUNTRIES.find((c) => c.iso2 === region);
      if (hit) return hit;
    }
  } catch {
    // ignore
  }
  return DEFAULT_COUNTRY;
}
