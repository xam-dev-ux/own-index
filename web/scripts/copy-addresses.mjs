// Dev only: copies the local fork's addresses (written by `make setup-fork`) into public/. Never committed.
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
const src = new URL("../../.fork/addresses.json", import.meta.url);
mkdirSync(new URL("../public/", import.meta.url), { recursive: true });
if (existsSync(src)) copyFileSync(src, new URL("../public/addresses.json", import.meta.url));
else console.warn("no .fork/addresses.json: run `make setup-fork` first");
