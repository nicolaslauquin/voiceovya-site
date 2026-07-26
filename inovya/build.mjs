import { cp, mkdir, rm } from "node:fs/promises";

await rm("dist", { recursive: true, force: true });
await mkdir("dist", { recursive: true });
await cp("index.html", "dist/index.html");
await cp("robots.txt", "dist/robots.txt");
await cp(".htaccess", "dist/.htaccess");
