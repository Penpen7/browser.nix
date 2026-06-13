# Update sources.json to the latest stable Brave and Google Chrome.
# Usage: nix run .#update
#
# No archives are downloaded: every hash comes from upstream metadata
# (GitHub release .sha256 sidecars, the Omaha update API, the apt Packages
# index), so this runs in seconds.

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
sources_file="$root/sources.json"

to_sri() {
  nix hash convert --hash-algo sha256 --to sri "$1"
}

# GitHub release assets publish a "<sha256>  <filename>" sidecar next to
# each asset.
gh_asset_hash() {
  to_sri "$(curl -fsSL "$1.sha256" | awk '{print $1}')"
}

# --- Brave ---
brave_version=$(curl -fsSL https://api.github.com/repos/brave/brave-browser/releases/latest \
  | jq -r '.tag_name | ltrimstr("v")')
echo "Brave: ${brave_version}" >&2

brave_base="https://github.com/brave/brave-browser/releases/download/v${brave_version}"
# darwin: use the dmg assets (the darwin zips lack the top-level code
# signature); linux: the deb assets, matching what nixpkgs' brave expects.
brave_url_darwin_arm64="${brave_base}/Brave-Browser-arm64.dmg"
brave_url_darwin_x64="${brave_base}/Brave-Browser-x64.dmg"
brave_url_linux_arm64="${brave_base}/brave-browser_${brave_version}_arm64.deb"
brave_url_linux_amd64="${brave_base}/brave-browser_${brave_version}_amd64.deb"
brave_hash_darwin_arm64=$(gh_asset_hash "$brave_url_darwin_arm64")
brave_hash_darwin_x64=$(gh_asset_hash "$brave_url_darwin_x64")
brave_hash_linux_arm64=$(gh_asset_hash "$brave_url_linux_arm64")
brave_hash_linux_amd64=$(gh_asset_hash "$brave_url_linux_amd64")

# --- Google Chrome (darwin) ---
# Query the Omaha update API: it returns a versioned permalink to the crx3
# update package (a zip containing the dmg) along with its sha256.
omaha=$(curl -fsSL -X POST "https://update.googleapis.com/service/update2/json" \
  -H "Content-Type: application/json" \
  -d '{"request":{"protocol":"3.1","acceptformat":"crx3","app":[{"appid":"com.google.Chrome","version":"0.0.0.0","updatecheck":{}}],"os":{"platform":"mac","arch":"arm64","version":"15.0"},"arch":"arm64","updater":"browser.nix"}}' \
  | sed "s/^)]}'//")
updatecheck=$(jq '.response.app[0].updatecheck' <<<"$omaha")

chrome_darwin_version=$(jq -r '.manifest.version' <<<"$updatecheck")
chrome_darwin_codebase=$(jq -r '[.urls.url[].codebase | select(startswith("https://dl.google.com/"))][0]' <<<"$updatecheck")
chrome_darwin_pkg=$(jq -r '.manifest.packages.package[0].name' <<<"$updatecheck")
chrome_darwin_url="${chrome_darwin_codebase}${chrome_darwin_pkg}"
chrome_darwin_hash=$(to_sri "$(jq -r '.manifest.packages.package[0].hash_sha256' <<<"$updatecheck")")
echo "Google Chrome (darwin): ${chrome_darwin_version}" >&2

# --- Google Chrome (linux) ---
# The apt repository's Packages index has the versioned deb path and its
# sha256. Linux and macOS stable versions can differ slightly.
chrome_linux_stanza=$(curl -fsSL "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages" \
  | awk -v RS= -v FS='\n' '$1=="Package: google-chrome-stable"')
chrome_linux_version=$(awk '$1=="Version:"{print $2}' <<<"$chrome_linux_stanza" | sed 's/-[0-9]*$//')
chrome_linux_url="https://dl.google.com/linux/chrome/deb/$(awk '$1=="Filename:"{print $2}' <<<"$chrome_linux_stanza")"
chrome_linux_hash=$(to_sri "$(awk '$1=="SHA256:"{print $2}' <<<"$chrome_linux_stanza")")
echo "Google Chrome (linux): ${chrome_linux_version}" >&2

jq -n \
  --arg brave_version "$brave_version" \
  --arg brave_url_darwin_arm64 "$brave_url_darwin_arm64" \
  --arg brave_hash_darwin_arm64 "$brave_hash_darwin_arm64" \
  --arg brave_url_darwin_x64 "$brave_url_darwin_x64" \
  --arg brave_hash_darwin_x64 "$brave_hash_darwin_x64" \
  --arg brave_url_linux_arm64 "$brave_url_linux_arm64" \
  --arg brave_hash_linux_arm64 "$brave_hash_linux_arm64" \
  --arg brave_url_linux_amd64 "$brave_url_linux_amd64" \
  --arg brave_hash_linux_amd64 "$brave_hash_linux_amd64" \
  --arg chrome_darwin_version "$chrome_darwin_version" \
  --arg chrome_darwin_url "$chrome_darwin_url" \
  --arg chrome_darwin_hash "$chrome_darwin_hash" \
  --arg chrome_linux_version "$chrome_linux_version" \
  --arg chrome_linux_url "$chrome_linux_url" \
  --arg chrome_linux_hash "$chrome_linux_hash" \
  '{
    brave: {
      version: $brave_version,
      src: {
        "aarch64-darwin": { url: $brave_url_darwin_arm64, hash: $brave_hash_darwin_arm64 },
        "x86_64-darwin": { url: $brave_url_darwin_x64, hash: $brave_hash_darwin_x64 },
        "aarch64-linux": { url: $brave_url_linux_arm64, hash: $brave_hash_linux_arm64 },
        "x86_64-linux": { url: $brave_url_linux_amd64, hash: $brave_hash_linux_amd64 }
      }
    },
    "google-chrome": {
      darwin: {
        version: $chrome_darwin_version,
        src: { url: $chrome_darwin_url, hash: $chrome_darwin_hash }
      },
      linux: {
        version: $chrome_linux_version,
        src: { url: $chrome_linux_url, hash: $chrome_linux_hash }
      }
    }
  }' > "$sources_file.tmp"
mv "$sources_file.tmp" "$sources_file"

echo "Wrote $sources_file" >&2
