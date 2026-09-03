import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "Care Net tasks", description: "Care Net Consultants sales tasks module" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en-ZA"><body>{children}</body></html>;
}
