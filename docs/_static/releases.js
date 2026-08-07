(function () {
  "use strict";

  const root = document.getElementById("release-downloads");
  if (!root) return;

  const repository = root.dataset.repository;
  const preferredTags = [
    "IPQ60XX-JD1800-6.12-WIFI-TPROXY",
    "IPQ60XX-JD1800-6.12-WIFI",
  ];

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB"];
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    return `${(bytes / Math.pow(1024, index)).toFixed(index ? 1 : 0)} ${units[index]}`;
  }

  function createAsset(asset) {
    const item = document.createElement("li");
    const link = document.createElement("a");
    link.href = asset.browser_download_url;
    link.textContent = asset.name;
    link.className = "download-button";
    const meta = document.createElement("span");
    meta.className = "download-meta";
    meta.textContent = `${formatBytes(asset.size)} · 下载 ${asset.download_count || 0} 次`;
    item.append(link, meta);
    return item;
  }

  function createRelease(release) {
    const card = document.createElement("section");
    card.className = "release-card";
    const heading = document.createElement("h2");
    heading.textContent = release.name || release.tag_name;
    const details = document.createElement("p");
    details.className = "release-date";
    const published = release.published_at ? new Date(release.published_at) : null;
    details.textContent = published
      ? `更新时间：${published.toLocaleString("zh-CN", { hour12: false })}`
      : "尚未发布";
    const assets = document.createElement("ul");
    assets.className = "asset-list";
    (release.assets || []).forEach((asset) => assets.appendChild(createAsset(asset)));
    if (!release.assets || release.assets.length === 0) {
      const empty = document.createElement("p");
      empty.textContent = "此 Release 暂无可下载文件。";
      card.append(heading, details, empty);
    } else {
      card.append(heading, details, assets);
    }
    return card;
  }

  fetch(`https://api.github.com/repos/${repository}/releases?per_page=100`, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((response) => {
      if (!response.ok) throw new Error(`GitHub API ${response.status}`);
      return response.json();
    })
    .then((releases) => {
      const byTag = new Map(releases.map((release) => [release.tag_name, release]));
      const selected = preferredTags.map((tag) => byTag.get(tag)).filter(Boolean);
      root.replaceChildren();
      if (selected.length === 0) {
        const empty = document.createElement("p");
        empty.textContent = "暂未找到 JDC-Arthur 固件 Release。";
        root.appendChild(empty);
        return;
      }
      selected.forEach((release) => root.appendChild(createRelease(release)));
    })
    .catch((error) => {
      const message = document.createElement("p");
      message.className = "release-error";
      message.textContent = `无法自动读取编译产物：${error.message}`;
      root.replaceChildren(message);
    });
})();
