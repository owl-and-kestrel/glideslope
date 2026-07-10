#!/usr/bin/env node

import { createHash, createPublicKey, verify } from "node:crypto";
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const flags = new Set(process.argv.slice(2));
const publish = flags.has("--publish");
const allowDirty = flags.has("--allow-dirty");
const allowUnsigned = flags.has("--allow-unsigned");
const releaseDir = process.env.GLIDESLOPE_RELEASE_DIR || path.join(root, "dist/release");
const zipPath = path.join(releaseDir, "Glideslope.zip");
const appcastPath = path.join(releaseDir, "appcast.xml");
const manifestPath = path.join(releaseDir, "glideslope-update.json");
const channel = process.env.GLIDESLOPE_RELEASE_CHANNEL || "stable";
const bucket = process.env.GLIDESLOPE_R2_BUCKET || "ok-release-artifacts";
const updateOrigin = validatedOrigin(process.env.GLIDESLOPE_UPDATE_ORIGIN || "https://updates.owlandkestrel.com");
const okOrigin = validatedOrigin(process.env.GLIDESLOPE_OK_BASE_URL || "https://owlandkestrel.com");
const chirpChannel = process.env.GLIDESLOPE_CHIRP_CHANNEL || "glideslope-updates";
const sparkleKey = process.env.GLIDESLOPE_SPARKLE_PRIVATE_KEY_FILE || "/Users/jon/.config/owl-kestrel/secrets/sparkle-ed25519-private-key";
const signUpdate = process.env.GLIDESLOPE_SIGN_UPDATE || path.join(root, ".build/artifacts/sparkle/Sparkle/bin/sign_update");

if (flags.has("--help")) {
  process.stdout.write("Usage: node scripts/publish-release.mjs [--publish] [--allow-dirty] [--allow-unsigned]\n");
  process.exit(0);
}
if (!/^[a-z0-9][a-z0-9-]{0,31}$/u.test(channel)) throw new Error("Invalid release channel.");
for (const required of [zipPath, appcastPath, manifestPath]) {
  if (!existsSync(required)) throw new Error(`Release artifact is missing: ${required}`);
}

const packageJSON = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
const manifestDocument = JSON.parse(await readFile(manifestPath, "utf8"));
const decoded = await decodeAndVerifyManifest(manifestDocument);
const payload = decoded.payload;
const version = String(packageJSON.version || "");
const build = Number(packageJSON.build);
if (!/^\d+(?:\.\d+){1,3}$/u.test(version) || !Number.isSafeInteger(build) || build <= 0) {
  throw new Error("package.json must contain a valid version and positive integer build.");
}
validateManifest(payload, { version, build, channel });
if (publish && payload.source.dirty && !allowDirty) throw new Error("Refusing to publish an artifact built from a dirty worktree.");
if (publish && !decoded.signatureVerified && !allowUnsigned) throw new Error("Refusing to publish an unsigned release manifest.");

const zip = await readFile(zipPath);
const appcast = await readFile(appcastPath);
const zipSha256 = sha256Bytes(zip);
const appcastSha256 = sha256Bytes(appcast);
const artifact = payload.artifacts.find((item) => item.platform === "macos");
if (artifact.sha256 !== zipSha256 || artifact.sizeBytes !== zip.length) throw new Error("ZIP bytes do not match the release manifest.");
if (payload.updateFeed.sha256 !== appcastSha256) throw new Error("Appcast bytes do not match the release manifest.");

const item = parseAppcast(appcast.toString("utf8"));
if (item.version !== version || item.build !== String(build)) throw new Error("Appcast version/build does not match package metadata.");
if (item.url !== artifact.url || item.length !== String(zip.length)) throw new Error("Appcast enclosure does not match the ZIP manifest.");
if (!item.signature) throw new Error("Appcast enclosure is missing an Ed25519 signature.");
const artifactURL = new URL(artifact.url);
const expectedArtifactPath = `/glideslope/releases/v${version}/${zipSha256}/Glideslope.zip`;
if (artifactURL.origin !== updateOrigin.origin || artifactURL.pathname !== expectedArtifactPath) {
  throw new Error("Artifact URL is not the content-addressed canonical R2 URL.");
}
const expectedFeedPath = `/glideslope/${channel}/appcast.xml`;
const feedURL = new URL(payload.updateFeed.url);
if (feedURL.origin !== updateOrigin.origin || feedURL.pathname !== expectedFeedPath) throw new Error("Update feed URL is not canonical.");

const artifactKey = artifactURL.pathname.slice(1);
const appcastKey = feedURL.pathname.slice(1);
const dedupeKey = `glideslope:${channel}:${version}:${build}:${zipSha256}`;
const trustPayload = {
  sourceSlug: "owl-and-kestrel", sourceName: "Owl + Kestrel", verifiedLabel: "Owl + Kestrel Official",
  homepageUrl: "https://owlandkestrel.com", productSlug: "glideslope", productName: "Glideslope",
  productSummary: "Native macOS usage-pressure gauge for Codex and Claude Code.", channel, version,
  artifactUrl: artifact.url, artifactSha256: zipSha256, manifestStatus: "published"
};
const chirpPayload = {
  channel: chirpChannel, kind: "event", subtype: "product.release_available",
  body: `Glideslope ${version} (${build}) is available. ${payload.downloadPageUrl}`,
  payload: { eventType: "product.release_available", dedupeKey, severity: "info", product: "glideslope", channel,
    version, build, releaseUrl: payload.downloadPageUrl, artifactSha256: zipSha256, sourceCommit: payload.source.commit }
};

const plan = { mode: publish ? "publish" : "dry-run", version, build, channel, bucket, artifactKey, appcastKey,
  artifactSha256: zipSha256, appcastSha256, manifestSignatureVerified: decoded.signatureVerified,
  publicationOrder: ["verify signatures", "upload/read back immutable ZIP", "upload/read back appcast", "publish Trust", "announce Chirp"],
  trustPayload, chirpPayload, source: payload.source };
if (!publish) {
  process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`);
  process.exit(0);
}

// Resolve every late dependency before the first remote write.
const trustKey = await credential("GLIDESLOPE_OK_API_KEY", "GLIDESLOPE_OK_API_KEY_FILE", path.join(root, ".ok-api-key.txt"));
const chirpKey = await credential("GLIDESLOPE_CHIRP_API_KEY", "GLIDESLOPE_CHIRP_API_KEY_FILE");
if (!trustKey) throw new Error("Set GLIDESLOPE_OK_API_KEY or GLIDESLOPE_OK_API_KEY_FILE.");
if (!chirpKey) throw new Error("Set GLIDESLOPE_CHIRP_API_KEY or GLIDESLOPE_CHIRP_API_KEY_FILE.");
if (!existsSync(sparkleKey) || !existsSync(signUpdate)) throw new Error("Sparkle signing key or sign_update is missing.");
if (((await stat(sparkleKey)).mode & 0o077) !== 0) throw new Error("Sparkle private key must be mode 600.");
await run(signUpdate, ["--ed-key-file", sparkleKey, "--verify", zipPath, item.signature]);
await run(signUpdate, ["--ed-key-file", sparkleKey, "--verify", appcastPath]);

const liveFeed = await publicRead(feedURL, true);
if (liveFeed) {
  const live = parseAppcast(liveFeed.toString("utf8"));
  const liveBuild = Number(live.build);
  if (!Number.isSafeInteger(liveBuild)) throw new Error("Live appcast has an invalid build.");
  if (liveBuild > build) throw new Error(`Refusing build ${build}; live build is ${liveBuild}.`);
  if (liveBuild === build && !liveFeed.equals(appcast)) throw new Error("Live appcast has the same build but different bytes.");
}

const temporary = await mkdtemp(path.join(os.tmpdir(), "glideslope-r2-"));
try {
  const existingPath = path.join(temporary, "existing.zip");
  const existing = await r2Get(artifactKey, existingPath);
  if (existing) {
    if (!(await readFile(existingPath)).equals(zip)) throw new Error("Immutable R2 artifact key already contains different bytes.");
  } else {
    await r2Put(artifactKey, zipPath, "application/zip", "public, max-age=31536000, immutable");
  }
  const publicZip = await publicRead(artifactURL, false);
  if (!publicZip.equals(zip)) throw new Error("Public ZIP readback did not match uploaded bytes.");

  if (!liveFeed || !liveFeed.equals(appcast)) {
    await r2Put(appcastKey, appcastPath, "application/xml; charset=utf-8", "public, max-age=60, must-revalidate");
  }
  const publicFeed = await publicRead(feedURL, false);
  if (!publicFeed.equals(appcast)) throw new Error("Public appcast readback did not match uploaded bytes.");
} finally {
  await rm(temporary, { recursive: true, force: true });
}

await requestJSON(new URL("/api/admin/trust/manifests", okOrigin), trustKey, { method: "POST", body: trustPayload });
const snapshot = await requestJSON(new URL(`/chirp/api?channel=${encodeURIComponent(chirpChannel)}&limit=100`, okOrigin), chirpKey);
const announced = Array.isArray(snapshot.records) && snapshot.records.some((record) => record?.payload?.dedupeKey === dedupeKey);
let chirpRecord = null;
if (!announced) {
  chirpRecord = await requestJSON(new URL("/chirp/api", okOrigin), chirpKey, { method: "POST", body: chirpPayload,
    headers: { "x-ok-agent-label": "Glideslope release publisher", "x-ok-agent-slug": "system/glideslope-release" } });
}
process.stdout.write(`${JSON.stringify({ ok: true, ...plan, trustPublished: true, chirpAnnounced: !announced,
  chirpDeduplicated: announced, chirpRecordId: chirpRecord?.record?.id || chirpRecord?.id || null }, null, 2)}\n`);

function validateManifest(value, expected) {
  if (value.schema !== "ok.product-update.v1" || value.appId !== "glideslope" || value.bundleId !== "com.owlandkestrel.glideslope"
    || value.version !== expected.version || value.build !== expected.build || value.channel !== expected.channel) throw new Error("Release manifest identity does not match package metadata.");
  if (!value.source || value.source.repository !== "https://github.com/owl-and-kestrel/glideslope.git" || !/^[0-9a-f]{40}$/u.test(value.source.commit || "")
    || typeof value.source.dirty !== "boolean" || value.source.buildConfiguration !== "release") throw new Error("Release manifest is missing exact source provenance.");
  if (!value.updateFeed || value.updateFeed.format !== "sparkle.appcast.v2" || !/^[0-9a-f]{64}$/u.test(value.updateFeed.sha256 || "")) throw new Error("Release manifest updateFeed is invalid.");
  if (!Array.isArray(value.artifacts) || value.artifacts.filter((x) => x.platform === "macos").length !== 1) throw new Error("Release manifest must contain exactly one macOS artifact.");
}

function parseAppcast(xml) {
  const one = (pattern, label) => {
    const values = [...xml.matchAll(pattern)].map((match) => match[1]);
    if (values.length !== 1) throw new Error(`Appcast must contain exactly one ${label}.`);
    return decodeXML(values[0]);
  };
  const enclosureMatches = [...xml.matchAll(/<enclosure\b([^>]*?)\/?\s*>/gu)];
  if (enclosureMatches.length !== 1) throw new Error("Appcast must contain exactly one enclosure.");
  const attrs = enclosureMatches[0][1];
  const attr = (name, label = name) => {
    const values = [...attrs.matchAll(new RegExp(`(?:^|\\s)(?:sparkle:)?${name}="([^"]*)"`, "gu"))].map((m) => decodeXML(m[1]));
    if (values.length !== 1) throw new Error(`Appcast enclosure must contain exactly one ${label}.`);
    return values[0];
  };
  return {
    version: one(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/gu, "short version"),
    build: one(/<sparkle:version>([^<]+)<\/sparkle:version>/gu, "build"),
    url: attr("url"), length: attr("length"), signature: attr("edSignature", "Ed25519 signature")
  };
}

function decodeXML(value) { return value.replaceAll("&amp;", "&").replaceAll("&quot;", '"').replaceAll("&lt;", "<").replaceAll("&gt;", ">"); }
function sha256Bytes(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function validatedOrigin(value) {
  const url = new URL(value); const loopback = ["127.0.0.1", "::1", "localhost"].includes(url.hostname);
  if ((url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) || url.username || url.password) throw new Error("Origins must use HTTPS or loopback HTTP without credentials.");
  return url;
}
async function run(file, args) { await execFileAsync(file, args, { cwd: root, maxBuffer: 4 * 1024 * 1024 }); }
async function wrangler(args) {
  const executable = process.env.GLIDESLOPE_WRANGLER || "npx";
  const prefix = executable === "npx" ? ["--yes", "wrangler"] : [];
  await run(executable, [...prefix, ...args]);
}
async function r2Get(key, destination) {
  try { await wrangler(["r2", "object", "get", `${bucket}/${key}`, "--file", destination, "--remote"]); return true; }
  catch (error) {
    const output = `${error.stderr || ""}\n${error.stdout || ""}`.replace(/\x1B\[[0-?]*[ -/]*[@-~]/gu, "");
    if (/does not exist|not found|404|NoSuchKey/iu.test(output)) return false;
    throw error;
  }
}
async function r2Put(key, source, contentType, cacheControl) {
  await wrangler(["r2", "object", "put", `${bucket}/${key}`, "--file", source, "--content-type", contentType, "--cache-control", cacheControl, "--remote"]);
}
async function publicRead(url, allow404) {
  const response = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(30_000) });
  if (allow404 && response.status === 404) return null;
  if (!response.ok) throw new Error(`Public readback failed (${response.status}) for ${url.pathname}`);
  return Buffer.from(await response.arrayBuffer());
}
async function requestJSON(url, token, options = {}) {
  const response = await fetch(url, { method: options.method || "GET", headers: { accept: "application/json", authorization: `Bearer ${token}`,
    ...(options.body ? { "content-type": "application/json" } : {}), ...options.headers }, body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(30_000) });
  const text = await response.text(); let parsed = {}; try { parsed = text ? JSON.parse(text) : {}; } catch {}
  if (!response.ok) throw new Error(`${url.pathname} failed (${response.status}): ${parsed.error || response.statusText}`);
  return parsed;
}
async function credential(valueName, fileName, defaultFile = "") {
  const direct = String(process.env[valueName] || "").trim(); if (direct) return direct;
  const file = String(process.env[fileName] || defaultFile).trim(); if (!file || !existsSync(file)) return "";
  if (((await stat(file)).mode & 0o077) !== 0) throw new Error(`${fileName} must point to a mode-600 file.`);
  return (await readFile(file, "utf8")).trim();
}
async function decodeAndVerifyManifest(document) {
  if (document.schema !== "ok.signed-manifest.v1") return { payload: document, signatureVerified: false };
  if (document.publisher?.id !== "owl-kestrel" || document.publisher?.domain !== "owlandkestrel.com"
    || document.publisher?.keyId !== (process.env.OK_RELEASE_KEY_ID || "ok-release-p256-v1") || document.signature?.alg !== "ECDSA_P256_SHA256_DER") throw new Error("Signed release manifest has unexpected publisher metadata.");
  const publicKeyPEM = await readReleasePublicKey(); const publicKey = createPublicKey(publicKeyPEM);
  const payloadBytes = decodeBase64URL(document.signedPayload, "signedPayload"); const signatureBytes = decodeBase64URL(document.signature?.value, "signature");
  if (!verify("sha256", payloadBytes, publicKey, signatureBytes)) throw new Error("Signed release manifest signature verification failed.");
  return { payload: JSON.parse(payloadBytes.toString("utf8")), signatureVerified: true };
}
async function readReleasePublicKey() {
  const direct = String(process.env.OK_RELEASE_PUBLIC_KEY_PEM || "").trim(); if (direct) return direct;
  const file = process.env.OK_RELEASE_PUBLIC_KEY_FILE || path.join(root, "config/ok-release-p256-v1.pub.pem");
  return (await readFile(file, "utf8")).trim();
}
function decodeBase64URL(value, label) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/u.test(value)) throw new Error(`Signed release manifest ${label} is invalid.`);
  const bytes = Buffer.from(value, "base64url"); if (bytes.toString("base64url") !== value) throw new Error(`Signed release manifest ${label} is non-canonical.`); return bytes;
}
