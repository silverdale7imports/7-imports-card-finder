import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "7 Imports Card Finder",
  description: "Search trading card singles at 7 Imports and reserve for in-store pickup."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
