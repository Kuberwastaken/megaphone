import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const siteDirectory = process.argv[2];
if (!siteDirectory) throw new Error("Usage: hydrate-website-release.mjs <site-directory>");

const response = await fetch("https://api.github.com/repos/Kuberwastaken/megaphone/releases?per_page=20", {
  headers: {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "megaphone-pages-deploy"
  }
});
if (!response.ok) throw new Error(`GitHub release lookup failed: ${response.status} ${response.statusText}`);

const releases = await response.json();
if (!Array.isArray(releases)) throw new Error("GitHub release lookup returned an unexpected response");

const isStableSemver = release =>
  !release.draft &&
  !release.prerelease &&
  /^v?\d+\.\d+\.\d+$/.test(String(release.tag_name || ""));
const stableReleases = releases.filter(isStableSemver);
const release = stableReleases[0];
if (!release) throw new Error("No stable semantic Megaphone release was found");
const version = String(release.tag_name || "").replace(/^v/i, "");
const dmg = release.assets?.find(asset => asset.name === "Megaphone.dmg");
if (!version || !release.published_at || !release.html_url || !dmg?.browser_download_url) {
  throw new Error("Latest GitHub release is missing required website metadata");
}

const escapeHTML = value => String(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#39;");

const firstBullet = String(release.body || "")
  .split("\n")
  .map(line => line.trim())
  .find(line => /^[-*]\s+/.test(line))
  ?.replace(/^[-*]\s+/, "")
  .replace(/\[([^\]]+)]\([^\)]+\)/g, "$1")
  .replace(/\s*\(#\d+\)\s*$/, "")
  .trim();
const fallbackHighlight = `Megaphone ${version} is now available.`;
const rawHighlight = firstBullet || fallbackHighlight;
const highlight = rawHighlight.length > 210
  ? `${rawHighlight.slice(0, 207).replace(/\s+\S*$/, "")}…`
  : rawHighlight;
const summary = rawHighlight.length > 125
  ? `${rawHighlight.slice(0, 122).replace(/\s+\S*$/, "")}…`
  : rawHighlight;
const releaseDate = new Intl.DateTimeFormat("en-US", {
  month: "long",
  day: "numeric",
  year: "numeric",
  timeZone: "UTC"
}).format(new Date(release.published_at));

const replacements = new Map([
  ["__MEGAPHONE_VERSION__", version],
  ["__MEGAPHONE_RELEASE_DATE__", releaseDate],
  ["__MEGAPHONE_RELEASE_DATE_ISO__", release.published_at],
  ["__MEGAPHONE_RELEASE_HIGHLIGHT__", highlight],
  ["__MEGAPHONE_RELEASE_SUMMARY__", summary],
  ["__MEGAPHONE_RELEASE_URL__", release.html_url],
  ["__MEGAPHONE_DMG_URL__", dmg.browser_download_url]
]);

for (const fileName of ["index.html", "llms.txt"]) {
  const path = join(siteDirectory, fileName);
  let contents = await readFile(path, "utf8");
  for (const [token, value] of replacements) {
    contents = contents.replaceAll(token, escapeHTML(value));
  }
  const unresolved = contents.match(/__MEGAPHONE_[A-Z_]+__/g);
  if (unresolved) throw new Error(`Unresolved release metadata in ${fileName}: ${unresolved.join(", ")}`);
  await writeFile(path, contents);
}

const updateManifest = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  releases: stableReleases.map(item => ({
    tag_name: item.tag_name,
    name: item.name,
    body: item.body,
    html_url: item.html_url,
    published_at: item.published_at,
    assets: (item.assets || [])
      .filter(asset => asset.name === "Megaphone.dmg")
      .map(asset => ({
        name: asset.name,
        browser_download_url: asset.browser_download_url,
        size: asset.size
      }))
  }))
};
await writeFile(
  join(siteDirectory, "updates.json"),
  `${JSON.stringify(updateManifest, null, 2)}\n`
);

console.log(`Hydrated website with Megaphone ${version}, published ${releaseDate}`);
