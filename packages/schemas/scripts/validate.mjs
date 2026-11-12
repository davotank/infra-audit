// Validates every example against its schema, then checks that the privacy rules reject bad evidence.
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const root = new URL("..", import.meta.url);
const load = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));

const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);

let failures = 0;
const validators = {};
const check = (label, schemaName, doc, shouldPass) => {
  const validate = (validators[schemaName] ??= ajv.compile(load(`schemas/${schemaName}.schema.json`)));
  const ok = validate(doc);
  const pass = ok === shouldPass;
  if (!pass) failures++;
  console.log(`${pass ? "ok  " : "FAIL"} ${label}${!ok && shouldPass ? " " + ajv.errorsText(validate.errors) : ""}`);
};

for (const name of ["tender", "evidence", "audit-report"]) {
  check(`${name} example is valid`, name, load(`examples/${name}.example.json`), true);
}

const ev = load("examples/evidence.example.json");
check("evidence rejects extra fields (e.g. deviceModel)", "evidence", { ...ev, deviceModel: "Pixel 9" }, false);
check("evidence rejects precise timestamps", "evidence", { ...ev, observedOn: "2026-11-10T08:13:44Z" }, false);
check("evidence rejects geohash finer than ~150 m", "evidence", { ...ev, approxLocation: { geohash: "tdr1v9qxyz" } }, false);
check(
  "evidence rejects media without metadata stripping",
  "evidence",
  { ...ev, media: [{ ...ev.media[0], metadataStripped: false }] },
  false,
);
const t = load("examples/tender.example.json");
check("tender rejects malformed GSTIN", "tender", { ...t, contractor: { ...t.contractor, idValue: "BADGSTIN" } }, false);
check("tender rejects PIN starting with 0", "tender", { ...t, location: { ...t.location, pincode: "060001" } }, false);

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nall schema checks passed");
