import type { Config } from "tailwindcss";
/** CNC tokens, copied from design/tokens/colors.css. Red is accent, overdue and failure only. */
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        cnc: {
          red: "#ED1B24", redDark: "#C1272D", redDeep: "#8B0000", redTint: "#FDE8E9", redSoft: "#FEEDED",
          ink: "#1E1E1E", mute: "#787878", line: "#E2E2E2", greyLight: "#F0F0F0", panel: "#F2F2F2",
          green: "#007749", greenTint: "#E6F1ED", blue: "#001489", blueTint: "#E6E8F3", yellow: "#FFB81C", yellowTint: "#FFF4DC", warn: "#7A5A12",
        },
      },
      fontFamily: { heading: ["Montserrat", "Segoe UI", "Arial", "sans-serif"], body: ["'Open Sans'", "Segoe UI", "Arial", "sans-serif"] },
      borderRadius: { sm: "6px", md: "10px", lg: "14px" },
      boxShadow: { card: "0 1px 3px rgba(0,0,0,.08), 0 4px 14px rgba(0,0,0,.06)" },
    },
  },
  plugins: [],
};
export default config;
