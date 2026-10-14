# 自动更新（Sparkle）与发布页

## Sparkle

应用内嵌 [Sparkle 2.10](https://sparkle-project.org/)（MIT）。`Info.plist`：

| 键 | 值 |
| --- | --- |
| `SUFeedURL` | `https://www.neardws.com/MijiaBar/appcast.xml` |
| `SUPublicEDKey` | `CCM7RPQimyjvvf3oCtszbmQ1hQArwEl1FwPQTVLolb4=`（公钥，可提交） |

**私钥**只在维护者机器上：

```
~/mijiabar-private/sparkle/eddsa_priv.key
```

Keychain 账户名：`mijiabar`。切勿把私钥或 `~/mijiabar-private/` 提交进仓库。

### 发版流程

1. `VERSION=x.y.z scripts/package.sh` — 签名、公证、生成 `docs/appcast.xml`
2. 把公证后的 `dist/MijiaBar-x.y.z.dmg` 上传到 GitHub Release `v x.y.z`
3. 提交并推送更新后的 `docs/appcast.xml`（以及本站 `docs/index.html` 若需改文案）到 `main`，GitHub Pages 会托管 appcast
4. 已安装 **带 Sparkle 的构建**（≥ 本次）的用户会自动/手动检查到更新

### 从 0.1.8 迁移

0.1.8 及更早没有 Sparkle，**不会**自动升上来。需要手动安装一次带 Sparkle 的版本（本站或 Release DMG），之后才走自动更新。

### 仅重签 appcast

```bash
VERSION=x.y.z DMG_PATH=dist/MijiaBar-x.y.z.dmg scripts/generate-appcast.sh
```

## GitHub Pages

站点文件在 `docs/`：`index.html`（英文）、`zh-CN.html`（简中）、`appcast.xml`。

仓库设置 → Pages → Source = **Deploy from a branch** → Branch **`main`** / folder **`/docs`**。

首次启用也可用：

```bash
gh api repos/neardws/MijiaBar/pages -X POST \
  -f build_type=legacy \
  -F 'source[branch]=main' \
  -F 'source[path]=/docs'
```

公开地址：<https://www.neardws.com/MijiaBar/>
