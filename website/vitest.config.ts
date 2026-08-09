import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  test: {
    globals: true,
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          environment: "jsdom",
          setupFiles: ["./vitest.setup.ts"],
          include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
        },
      },
      {
        extends: true,
        test: {
          name: "integration",
          environment: "node",
          setupFiles: ["./vitest.setup.ts"],
          include: ["src/**/*.int.test.ts"],
          // Integration files share one live Firestore emulator and each
          // wipes collections in beforeEach (resetFirestore), so running them
          // in parallel lets one file clear data another just seeded. Harmless
          // while only one integration file existed; required from the moment
          // a second one was added.
          fileParallelism: false,
        },
      },
    ],
  },
});
