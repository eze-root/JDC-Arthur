# 仓库维护指南

## 上游关系

- 上游仓库：[`breeze303/openwrt-ci`](https://github.com/breeze303/openwrt-ci)
- 上游分支：`main`
- 本仓库分支：`main`

同步时必须使用普通 merge 并保留双方历史，不要 force push。发生冲突时，优先
保护以下本仓库定制：

- `.github/workflows/0-JD1800*.yml`
- `configs/0-jd1800*.config`
- `diy-jd1800.sh`
- `files/` 下的默认网络、Sing-box 与实验室环境配置
- `docs/` 下的 JDC-Arthur 使用说明和改进记录

建议的同步步骤：

```bash
git remote add upstream https://github.com/breeze303/openwrt-ci.git
git fetch upstream main
git switch -c agent/sync-upstream
git merge --no-ff upstream/main
```

合并后至少检查工作流 YAML、`.config` 重复键、冲突标记和文档构建，再通过
Draft PR 合入 `main`。

## 改进记录约定

每次修改都在 [改进记录](changelog.md) 的最上方追加一条，包括：

1. 修改日期和目的；
2. 用户可见的变化；
3. 对已有固件或配置的兼容性影响；
4. 实际完成的验证，以及尚未验证的部分。

纯格式调整可以合并记录；构建逻辑、默认网络、安全设置和固件包变化必须单独
说明。

## GitHub Pages

`build-docs.yml` 在 `main` 的文档相关文件变化后自动构建 Sphinx，并通过 GitHub
Pages 官方部署流程发布。仓库需要在 **Settings → Pages → Build and deployment**
中将 Source 设为 **GitHub Actions**。

下载页在浏览器中读取 GitHub Releases API，因此固件工作流更新 Release 后，
页面会自动显示新文件，无需重新部署 Pages。
