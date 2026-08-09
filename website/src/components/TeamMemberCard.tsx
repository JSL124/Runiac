"use client";

import Image from "next/image";
import { useState } from "react";
import type { KeyboardEvent, MouseEvent } from "react";
import type { TeamMember } from "@/lib/team";

type TeamMemberCardProps = {
  member: TeamMember;
};

export function TeamMemberCard({ member }: TeamMemberCardProps) {
  const [flipped, setFlipped] = useState(false);
  const hasSocials = Boolean(member.github || member.linkedin || member.email);

  const toggle = () => {
    setFlipped((current) => !current);
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    toggle();
  };

  const stopCardToggle = (event: MouseEvent<HTMLAnchorElement>) => {
    event.stopPropagation();
  };

  return (
    <article className={`team-flip-card h-full ${flipped ? "is-flipped" : ""}`}>
      <div
        className="team-flip-card-hit-area"
        onClick={toggle}
        onKeyDown={handleKeyDown}
        role="button"
        tabIndex={0}
        aria-pressed={flipped}
        aria-label={`${member.name} profile card. ${
          flipped ? "Show photo side" : "Show details side"
        }.`}
      >
        <div className="team-flip-card-inner">
          <div className="team-flip-card-face team-flip-card-front">
            <div className="team-flip-photo">
              <Image
                src={member.photo}
                alt={`${member.name}, ${member.role}`}
                fill
                sizes="(min-width: 1024px) 28vw, (min-width: 768px) 45vw, 88vw"
                className="object-cover object-top"
              />
              <div className="team-flip-photo-shade" aria-hidden="true" />
            </div>
            <div className="team-flip-meta">
              <h3 className="text-xl font-semibold leading-tight text-white">
                {member.name}
              </h3>
              <p className="mt-2 text-xs font-bold uppercase tracking-[0.16em] text-accent-soft">
                {member.role}
              </p>
            </div>
          </div>

          <div className="team-flip-card-face team-flip-card-back">
            <div className="flex h-full flex-col justify-center p-6 text-center sm:p-7">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand">
                {member.role}
              </p>
              <h3 className="mt-3 text-2xl font-semibold leading-tight text-foreground">
                {member.name}
              </h3>
              <p className="mt-5 text-sm leading-relaxed text-muted">
                {member.bio}
              </p>

              {hasSocials && (
                <div className="mt-7 flex items-center justify-center gap-3">
                  {member.github && (
                    <a
                      href={member.github}
                      target="_blank"
                      rel="noopener noreferrer"
                      onClick={stopCardToggle}
                      aria-label={`${member.name} GitHub`}
                      className="team-social-link"
                    >
                      <GithubIcon />
                    </a>
                  )}
                  {member.linkedin && (
                    <a
                      href={member.linkedin}
                      target="_blank"
                      rel="noopener noreferrer"
                      onClick={stopCardToggle}
                      aria-label={`${member.name} LinkedIn`}
                      className="team-social-link"
                    >
                      <LinkedInIcon />
                    </a>
                  )}
                  {member.email && (
                    <a
                      href={`mailto:${member.email}`}
                      onClick={stopCardToggle}
                      aria-label={`Email ${member.name}`}
                      className="team-social-link"
                    >
                      <MailIcon />
                    </a>
                  )}
                </div>
              )}

              <p className="mt-6 text-[11px] font-semibold uppercase tracking-[0.14em] text-muted/70">
                Hover or click to flip
              </p>
            </div>
          </div>
        </div>
      </div>
    </article>
  );
}

function GithubIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 .5C5.73.5.5 5.73.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.56 0-.28-.01-1.02-.02-2-3.2.7-3.88-1.54-3.88-1.54-.52-1.33-1.28-1.69-1.28-1.69-1.05-.72.08-.71.08-.71 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.71 1.26 3.37.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.04 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.78 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.58.24 2.75.12 3.04.74.81 1.18 1.83 1.18 3.09 0 4.41-2.69 5.38-5.26 5.67.41.36.77 1.06.77 2.14 0 1.54-.01 2.78-.01 3.16 0 .31.21.68.8.56A10.52 10.52 0 0 0 23.5 12C23.5 5.73 18.27.5 12 .5Z" />
    </svg>
  );
}

function LinkedInIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M20.45 20.45h-3.56v-5.57c0-1.33-.02-3.04-1.85-3.04-1.85 0-2.14 1.45-2.14 2.94v5.67H9.35V9h3.42v1.56h.05c.48-.9 1.64-1.85 3.37-1.85 3.6 0 4.27 2.37 4.27 5.46v6.28ZM5.34 7.43a2.06 2.06 0 1 1 0-4.13 2.06 2.06 0 0 1 0 4.13ZM7.12 20.45H3.55V9h3.57v11.45ZM22.22 0H1.77C.79 0 0 .77 0 1.72v20.56C0 23.23.79 24 1.77 24h20.45c.98 0 1.78-.77 1.78-1.72V1.72C24 .77 23.2 0 22.22 0Z" />
    </svg>
  );
}

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M3.75 6.75h16.5a1.5 1.5 0 0 1 1.5 1.5v7.5a1.5 1.5 0 0 1-1.5 1.5H3.75a1.5 1.5 0 0 1-1.5-1.5v-7.5a1.5 1.5 0 0 1 1.5-1.5Z"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path
        d="m3 8 9 6 9-6"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
      />
    </svg>
  );
}
