# Site assets

Screenshots, device art and the share image live in Cloudflare R2 (bucket `neardws-files`, prefix `mijiabar/site/`), served from
`https://files.neardws.com/mijiabar/site/{shots/<lang>,art}/*.webp` and `.../og.jpg`.

`scripts/site-shots.sh` still writes them to `docs/assets/` locally; upload that output to R2 and do not commit it (it is gitignored).
