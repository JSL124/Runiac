"use client";

import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  type ChartConfig,
} from "@/components/ui/chart";
import type { ActiveUsersPoint } from "@/lib/admin/types";

const chartConfig = {
  activeUsers: {
    label: "Active users",
    color: "#001e62",
  },
} satisfies ChartConfig;

type TooltipItem = { value?: number | string; payload?: ActiveUsersPoint };

function ActiveUsersTooltip({
  active,
  payload,
}: {
  active?: boolean;
  payload?: TooltipItem[];
}) {
  if (!active || !payload?.length) {
    return null;
  }

  const point = payload[0]?.payload;

  if (!point) {
    return null;
  }

  return (
    <div className="rounded-lg border border-border bg-white px-3 py-2 text-xs shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]">
      <p className="font-bold text-brand">{point.label}</p>
      <p className="mt-0.5 font-mono font-semibold tabular-nums text-foreground">
        {point.activeUsers.toLocaleString("en-GB")} active
      </p>
    </div>
  );
}

export function ActiveUsersChart({ data }: { data: ActiveUsersPoint[] }) {
  const label =
    "Monthly active users trend from " +
    `${data[0]?.label ?? ""} to ${data[data.length - 1]?.label ?? ""}, ` +
    "reported by the backend.";

  return (
    <div role="img" aria-label={label}>
      <ChartContainer
        config={chartConfig}
        className="aspect-[3/1] min-h-[180px] w-full"
      >
        <AreaChart
          accessibilityLayer
          data={data}
          margin={{ top: 10, right: 12, left: 0, bottom: 0 }}
        >
          <defs>
            <linearGradient id="activeUsersFill" x1="0" y1="0" x2="0" y2="1">
              <stop
                offset="5%"
                stopColor="var(--color-activeUsers)"
                stopOpacity={0.2}
              />
              <stop
                offset="95%"
                stopColor="var(--color-activeUsers)"
                stopOpacity={0.02}
              />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="#e4e5f3" strokeDasharray="4 4" vertical={false} />
          <XAxis
            dataKey="label"
            axisLine={false}
            tickLine={false}
            tickMargin={10}
            interval={0}
          />
          <YAxis
            axisLine={false}
            tickLine={false}
            width={44}
            tickMargin={6}
            tickFormatter={(value) => `${Math.round(Number(value) / 1000)}k`}
          />
          <ChartTooltip
            cursor={{ stroke: "var(--border)", strokeWidth: 1.5 }}
            content={<ActiveUsersTooltip />}
          />
          <Area
            type="monotone"
            dataKey="activeUsers"
            stroke="var(--color-activeUsers)"
            strokeWidth={2.5}
            fill="url(#activeUsersFill)"
            dot={{ r: 3, fill: "#001e62", strokeWidth: 0 }}
            activeDot={{ r: 5, fill: "var(--accent)", strokeWidth: 0 }}
          />
        </AreaChart>
      </ChartContainer>
    </div>
  );
}
