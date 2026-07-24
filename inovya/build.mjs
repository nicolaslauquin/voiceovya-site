import { cp, mkdir, rm } from "node:fs/promises";

await rm("dist", { recursive: true, force: true });
await mkdir("dist/server", { recursive: true });
await mkdir("dist/assets", { recursive: true });
await cp("index.html", "dist/assets/index.html");
await cp("og.png", "dist/assets/og.png");
await cp("worker.js", "dist/server/index.js");
