# 自动更新（Sparkle）与发布页

## 小屋风格包（手动维护，不属于发版脚本）

温馨木屋始终内置在 SwiftPM resource bundle。其余四包默认仍随 App 打包；R2 尚未上传时不要切换精简模式。
此流程不修改版本号、appcast 或 Sparkle，不需要把任何 R2 凭据写入仓库。

1. 素材变更时更新 `assets/house/styles/<id>/manifest.json` 的整数 `version`；已经上传的版本路径不可覆盖。
2. 执行 `scripts/build-style-packs.sh`（或指定输出目录）。输出 `dist/style-packs/<id>/<version>.zip` 和 `index.json`，
   同时生成 `Sources/MijiaBarApp/Resources/House/style-packs.json`。将该小型索引与素材修改一起提交，不提交 ZIP。
3. 执行 `scripts/build-style-packs.sh --check`：在临时目录重新构建，核对签入索引里的 SHA-256 和字节数。
   构建按路径排序、固定 2020-01-01 时间戳、固定 UNIX 文件权限、无 extra/comment 元数据（等效 `zip -X`）。
   使用 ZIP_STORED，PNG 本身已经压缩；避免 zlib/zip 版本差异改变哈希。同一输入字节产生完全相同的 ZIP。
4. 维护者在已认证的本机手动上传到绑定 `files.neardws.com` 的 R2 bucket，例如：

   ```bash
   scripts/build-style-packs.sh
   # BUCKET 是维护者的实际 bucket 名称；不要在脚本或仓库保存凭据。
   for id in japanese modern light-wood walnut; do
     version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "assets/house/styles/$id/manifest.json")
     wrangler r2 object put "$BUCKET/mijiabar/house/styles/$id/$version.zip" --remote \
       --file "dist/style-packs/$id/$version.zip" --content-type application/zip
   done
   wrangler r2 object put "$BUCKET/mijiabar/house/styles/index.json" --remote \
     --file dist/style-packs/index.json --content-type application/json
   ```

   也可以使用 R2 Dashboard 上传同样的 object keys。远端 index 方便维护者查看，客户端只信任随签名 App 内置的索引。
5. 维护者核对 HTTPS 公开 URL 可直接访问（不重定向），下载字节数和 SHA-256 与索引一致后，才使用
   `HOUSE_STYLE_BUNDLE=default scripts/package.sh`。默认 `HOUSE_STYLE_BUNDLE=all` 行为保持不变。
   `package.sh` 会清空 `dist/`，因此先上传或将包构建到独立目录，再进行 App 打包。
6. `scripts/verify-app-bundle.sh <App>` 总是检查默认素材与内置索引；指定 `HOUSE_STYLE_BUNDLE=all|default` 可验证
   对应模式，不指定时自动检测。可选风格仅出现一部分会失败。不要通过本步骤发布 App 或生成 appcast。

### 体积实测（当前四包 version 1）

`du -sk assets/house/styles/<id>/{modules,classic}`（不存在的 classic 忽略）与脚本 ZIP 输出：

| 风格 | modules + classic 磁盘占用（KiB） | ZIP 字节数 | 下载显示（MB，十进制） |
| --- | ---: | ---: | ---: |
| Japanese | 6,116 | 6,122,702 | 6.1 |
| Modern | 6,400 | 6,407,726 | 6.4 |
| Light wood | 9,524 | 9,563,089 | 9.6 |
| Walnut | 8,848 | 8,892,488 | 8.9 |
| 总计 | 30,888 | 30,986,005 | 31.0 |

精简模式移除约 30.2 MiB 的四包素材磁盘占用（不含极小的 manifest），而非声称 DMG 恰好缩小同样数值；
DMG 压缩、文件系统分配与签名都会影响最终大小。本次仅测量素材与 ZIP，未打包、公证或发布。

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
3. 运行 `python3 scripts/gen-site.py`（网页里的版本号取自 appcast），把更新后的 `docs/appcast.xml` 和 `docs/*.html` 提交并推送到 `main`，GitHub Pages 会托管 appcast
4. 已安装 **带 Sparkle 的构建**（≥ 本次）的用户会自动/手动检查到更新

### 从 0.1.8 迁移

0.1.8 及更早没有 Sparkle，**不会**自动升上来。需要手动安装一次带 Sparkle 的版本（本站或 Release DMG），之后才走自动更新。

### 仅重签 appcast

```bash
VERSION=x.y.z DMG_PATH=dist/MijiaBar-x.y.z.dmg scripts/generate-appcast.sh
```

## GitHub Pages

站点文件在 `docs/`：`index.html`（英文）和 `zh-CN.html`（简体中文），由 `scripts/gen-site.py` 根据 `site/template.html` 和 `i18n/site/*.json` 生成，不要直接改（繁体中文等页面稳定后再加，译稿在 `i18n/site/drafts/zh-Hant.json`）；图片在 `docs/assets/`（`scripts/site-shots.sh` 生成）；另有 `appcast.xml`。

根页面会按 `?lang=`、访客在语言菜单里的选择、浏览器语言依次决定是否跳转到中文页面（繁体中文浏览器也去简体页面）；旧链接 `index.html?lang=zh` 仍然有效。

仓库设置 → Pages → Source = **Deploy from a branch** → Branch **`main`** / folder **`/docs`**。

首次启用也可用：

```bash
gh api repos/neardws/MijiaBar/pages -X POST \
  -f build_type=legacy \
  -F 'source[branch]=main' \
  -F 'source[path]=/docs'
```

公开地址：<https://www.neardws.com/MijiaBar/>
