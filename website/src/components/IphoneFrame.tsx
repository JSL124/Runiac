// Shared iPhone mockup frame. Renders an app screenshot inside the real device
// asset (public/iphone-frame.png — a transparent-screen PNG): the screenshot
// sits in the screen area and the frame (bezel + dynamic island + buttons)
// overlays it. Screen geometry was pixel-measured from the source asset
// (inset left 2.88% / top 0.96%, size 94.72% x 98.06%). The screenshot corner
// radius uses container query units (9cqw = 9% of the frame width, circular and
// resolution-independent) so the same component looks right at any size — the
// full-size marketing render and the small admin preview alike.
//
// No hooks, so it is safe to use from both server and client components.

export function IphoneFrame({
  src,
  alt,
  className,
}: {
  src: string;
  alt: string;
  className?: string;
}) {
  return (
    <div
      className={`relative aspect-[1000/2064] [container-type:inline-size] ${
        className ?? "mx-auto w-full max-w-[19rem]"
      }`}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt={alt}
        className="absolute left-[2.88%] top-[0.96%] h-[98.06%] w-[94.72%] rounded-[9cqw] object-cover object-top"
      />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/iphone-frame.png"
        alt=""
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 h-full w-full"
      />
    </div>
  );
}
