// Copies an addresses file into public/. Never commits the fork one.
//   (no argument)  dev: the local fork's addresses written by `make setup-fork`
//   mainnet        build: web/addresses.mainnet.json, the deployed contracts. Public data, committed on purpose.
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
const mainnet = process.argv[2] === "mainnet";
const src = new URL(mainnet ? "../addresses.mainnet.json" : "../../.fork/addresses.json", import.meta.url);
mkdirSync(new URL("../public/", import.meta.url), { recursive: true });
if (existsSync(src)) copyFileSync(src, new URL("../public/addresses.json", import.meta.url));
else if (mainnet) { console.error("web/addresses.mainnet.json is missing"); process.exit(1); }
else console.warn("no .fork/addresses.json: run `make setup-fork` first");
