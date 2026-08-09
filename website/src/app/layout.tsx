// The root layout wrapping every page — public site and admin console alike.
//
// It deliberately holds almost nothing: fonts, global styles and default
// metadata. The admin console has its own nested layout for its chrome and
// auth, so keeping this shell empty is what lets the two live in one app
// without the marketing pages paying for the console.

import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Runiac — Build a running habit that lasts.",
  description:
    "Runiac helps beginner runners stay consistent with safe plans, gentle reminders, streaks, XP progress, and supportive post-run feedback.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${inter.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col bg-background text-foreground">
        {children}
      </body>
    </html>
  );
}
