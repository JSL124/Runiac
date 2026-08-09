"use client";

import { useEffect, useState } from "react";

export function FeatureHeroScrollWash() {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    let frame = 0;

    const updateProgress = () => {
      cancelAnimationFrame(frame);

      frame = requestAnimationFrame(() => {
        const rawProgress = Math.min(window.scrollY / 420, 1);
        const easedProgress = 1 - Math.pow(1 - rawProgress, 3);
        setProgress(easedProgress);
      });
    };

    updateProgress();
    window.addEventListener("scroll", updateProgress, { passive: true });

    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", updateProgress);
    };
  }, []);

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_38%,rgba(255,255,255,0.34),rgba(255,255,255,0.18)_44%,rgba(255,255,255,0.06)_100%)] transition-[opacity,backdrop-filter,filter] duration-300 ease-out"
      style={{
        opacity: progress * 0.82,
        backdropFilter: `blur(${progress * 5}px) saturate(${1 - progress * 0.18})`,
        filter: `brightness(${1 + progress * 0.06})`,
        zIndex: -5,
      }}
    />
  );
}
