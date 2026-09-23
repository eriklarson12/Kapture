// The DMG name carries the version, so resolve the latest asset at load time.
// On any failure the button keeps its fallback href: the latest release page.
(async () => {
  const button = document.getElementById("download");
  try {
    const response = await fetch("https://api.github.com/repos/eriklarson12/Kapture/releases/latest");
    if (!response.ok) return;
    const release = await response.json();
    const dmg = release.assets.find((asset) => asset.name.endsWith(".dmg"));
    if (!dmg) return;
    button.href = dmg.browser_download_url;
    button.textContent = `Download ${release.tag_name}`;
  } catch {}
})();
