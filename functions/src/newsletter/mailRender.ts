// Every outgoing message is a plain object matching the Trigger Email
// extension's documented contract: { to, message: { subject, html, text,
// headers? } }. Nothing here imports the extension or any mail-sending
// package — writing this shape into `mail/{autoId}` is the entire
// integration, and the SMTP provider behind it is configured separately by
// the operator, so this module stays provider-agnostic by construction.
export type MailDocument = {
  readonly to: string;
  readonly message: {
    readonly subject: string;
    readonly html: string;
    readonly text: string;
    readonly headers?: Readonly<Record<string, string>>;
  };
};

const LINK_PATTERN = /\[([^\]]+)\]\(([^)\s]+)\)/g;

/**
 * Minimal, dependency-free "markdown" renderer for campaign bodies: blank
 * lines separate paragraphs, single newlines become line breaks, and
 * `[text](url)` becomes a link. Nothing else (no bold/italic/headings/
 * lists) is supported. This is a deliberate choice, not an oversight — the
 * task forbids new dependencies, and the admin console's campaign composer
 * only ever needs simple prose plus the occasional link, so a real markdown
 * library would be pulling in a parser/AST/renderer for a feature surface
 * this small.
 */
export function renderMarkdownLite(markdown: string): { readonly html: string; readonly text: string } {
  const paragraphs = markdown
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph.length > 0);

  const html = paragraphs.map((paragraph) => `<p>${renderParagraphHtml(paragraph)}</p>`).join("\n");
  const text = paragraphs.map((paragraph) => renderParagraphText(paragraph)).join("\n\n");
  return { html, text };
}

function renderParagraphHtml(paragraph: string): string {
  // Escape the WHOLE paragraph first, then substitute links on the
  // already-escaped string — the captured text/url groups are therefore
  // already-escaped fragments and must not be escaped a second time (that
  // would turn "&amp;" into "&amp;amp;").
  const escaped = escapeHtml(paragraph);
  const withLinks = escaped.replace(LINK_PATTERN, (_match, text: string, url: string) => `<a href="${url}">${text}</a>`);
  return withLinks.split("\n").join("<br>");
}

function renderParagraphText(paragraph: string): string {
  return paragraph.replace(LINK_PATTERN, (_match, text: string, url: string) => `${text} (${url})`);
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function buildConfirmationMail(args: { readonly to: string; readonly confirmUrl: string }): MailDocument {
  const confirmUrl = escapeHtml(args.confirmUrl);
  return {
    to: args.to,
    message: {
      subject: "Confirm your Runiac newsletter subscription",
      html:
        `<p>Thanks for signing up for the Runiac newsletter! Please confirm your subscription by clicking the link below.</p>` +
        `<p><a href="${confirmUrl}">Confirm my subscription</a></p>` +
        `<p>If you did not request this, you can safely ignore this email.</p>`,
      text:
        `Thanks for signing up for the Runiac newsletter! Confirm your subscription:\n${args.confirmUrl}\n\n` +
        `If you did not request this, you can safely ignore this email.`,
    },
  };
}

/**
 * Every campaign email — real send or test send — must carry the
 * unsubscribe link in both the html and text bodies, AND a List-Unsubscribe
 * header so mail clients like Gmail render a native one-click "Unsubscribe"
 * affordance next to the sender. Only the classic `List-Unsubscribe: <url>`
 * form is set (no `List-Unsubscribe-Post` / RFC 8058 one-click), because
 * one-click requires a POST endpoint that skips confirmation entirely, and
 * this module only exposes a GET endpoint — see unsubscribeNewsletter.ts's
 * file header for why GET was the deliberate choice there.
 */
export function buildCampaignMail(args: {
  readonly to: string;
  readonly subject: string;
  readonly bodyMarkdown: string;
  readonly unsubscribeUrl: string;
}): MailDocument {
  const rendered = renderMarkdownLite(args.bodyMarkdown);
  const unsubscribeUrl = escapeHtml(args.unsubscribeUrl);
  return {
    to: args.to,
    message: {
      subject: args.subject,
      html: `${rendered.html}\n<p><a href="${unsubscribeUrl}">Unsubscribe from this newsletter</a></p>`,
      text: `${rendered.text}\n\nUnsubscribe from this newsletter: ${args.unsubscribeUrl}`,
      headers: { "List-Unsubscribe": `<${args.unsubscribeUrl}>` },
    },
  };
}
