#!/usr/bin/env python3
"""生成网站 docs/index.html 及各语言页面（GitHub Pages 从 docs/ 发布）。

模板：site/template.html；文案：i18n/site/<lang>.json（以 en.json 为准，缺键报错）。
目前只发布英文和简体中文；其他语言的译稿在 i18n/site/drafts/，页面稳定后再加回 LANGS（加回前不用更新它们）。
Agent 安装提示直接取自 Sources/MijiaCore/AgentPrompt.swift，版本号取自 docs/appcast.xml。
截图和插画由 scripts/site-shots.sh 生成到 docs/assets/。

用法：python3 scripts/gen-site.py          # 生成
      python3 scripts/gen-site.py --check  # 只检查生成结果是否最新，不写文件
"""
import html, json, os, re, sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

APP_LANGS = [('en', 'English'), ('zh-Hans', '简体中文'), ('zh-Hant', '繁體中文'), ('de', 'Deutsch'), ('fr', 'Français'),
             ('es', 'Español'), ('it', 'Italiano'), ('ru', 'Русский'), ('ja', '日本語')]
SITE = 'https://www.neardws.com/MijiaBar/'
# 截图、插画、分享图放在 R2（neardws-files 桶 mijiabar/site/），不进仓库；上传见 docs/assets/README.md
CDN = 'https://files.neardws.com/mijiabar/site'
REPO = 'https://github.com/neardws/MijiaBar'
CLI = '/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar'
# (文案文件, 页面代码 = 文件名 / 截图目录, html lang, hreflang, og:locale, Swift AppLang, 本语言名称)
# 加回其他语言时照这个格式写，例如 ('ja', 'ja', 'ja', 'ja', 'ja_JP', 'ja', '日本語')，并在 scripts/site-shots.sh 里加上截图
LANGS = [
    ('en', 'en', 'en', 'en', 'en_US', 'en', 'English'),
    ('zh-Hans', 'zh-CN', 'zh-CN', 'zh-Hans', 'zh_CN', 'zhHans', '简体中文'),
]
# 设备阵列：(插画文件名, 文案键)
LINEUP = [('ac', 'd_ac'), ('fan', 'd_fan'), ('bulb', 'd_light'), ('plug', 'd_plug'), ('camera', 'd_camera'), ('doorbell', 'd_doorbell'),
          ('tv', 'd_tv'), ('speaker', 'd_speaker'), ('air-purifier', 'd_air'), ('purifier', 'd_water'), ('heater', 'd_heater'),
          ('dehumidifier', 'd_dehum'), ('cooker', 'd_kitchen'), ('printer', 'd_printer'), ('thermo', 'd_thermo'),
          ('motion', 'd_motion'), ('contact', 'd_contact'), ('leak', 'd_leak')]
FAQ = 8


def page_file(code): return 'index.html' if code == 'en' else f'{code}.html'
def page_url(code): return SITE if code == 'en' else SITE + page_file(code)
def page_href(code): return './' if code == 'en' else page_file(code)
def doc_suffix(code): return '' if code == 'en' else '.' + code


def attr(s):
    return html.escape(re.sub(r'<[^>]+>', '', s.replace('<br>', ' ')), quote=True)


def swift_prompts():
    src = open('Sources/MijiaCore/AgentPrompt.swift', encoding='utf-8').read()
    out = {}
    for case, body in re.findall(r'case \.(\w+): t = "((?:[^"\\]|\\.)*)"', src):
        out[case] = body.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
    return out


def version():
    m = re.search(r'<sparkle:shortVersionString>([^<]+)<', open('docs/appcast.xml', encoding='utf-8').read())
    return m.group(1).strip() if m else ''


def dots(items):
    return '<span class="dot" aria-hidden="true">·</span>'.join(items)


def render(tpl, s, lang, prompts, ver):
    src, code, hl, hreflang, locale, swift, name = lang
    v = dict(s)
    ver_span = f'<span data-ver>{ver}</span>'
    size = '<span hidden><span class="dot" aria-hidden="true">·</span></span><span data-size hidden></span>'
    v['hero_fine'] = dots(s['hero_fine'].split('|'))
    v['final_fine'] = dots(x.replace('{v}', ver_span) + (size if '{v}' in x else '') for x in s['final_fine'].split('|'))
    v['menubar'] = ''.join(f'<span>{html.escape(x)}</span>' for x in s['menubar'].split('|'))
    v['html_lang'], v['og_locale'], v['shots'], v['lang_name'] = hl, locale, code, name
    v['canonical'] = page_url(code)
    v['og_image'] = CDN + '/og.jpg'
    v['cdn'] = CDN
    v['alternates'] = '\n'.join([f'<link rel="alternate" hreflang="{l[3]}" href="{page_url(l[1])}">' for l in LANGS]
                                + [f'<link rel="alternate" hreflang="x-default" href="{SITE}">'])
    v['redirect'] = redirect_script() if code == 'en' else ''
    v['lang_menu'] = lang_links(code, 10)
    v['lang_footer'] = lang_links(code, 8)
    # App 支持的 9 种界面语言（不是网站语言），用本语言名称
    v['lang_names'] = ' '.join(f'<span lang="{c}">{n}</span>' for c, n in APP_LANGS)
    v['lineup'] = '\n'.join(lineup_item(a, s[k]) for a, k in LINEUP)
    v['faq'] = '\n'.join(
        f'        <details><summary>{s[f"q{i}"]}<svg viewBox="0 0 14 14" aria-hidden="true"><path d="M7 1.5v11M1.5 7h11"/></svg></summary><p>{s[f"a{i}"]}</p></details>'
        for i in range(1, FAQ + 1))
    raw = f'https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP{doc_suffix(code)}.md'
    # 长网址和路径在 / 后面允许换行
    wbr = lambda t: re.sub(r'(?<=[^/])/(?=[^/])', '/<wbr>', t)
    p = wbr(html.escape(prompts[swift].replace('{CLI}', CLI))).replace('{URL}', f'<span class="u">{wbr(raw)}</span>')
    v['prompt'] = p
    v['guide_url'] = f'{REPO}/blob/main/docs/AGENT_SETUP{doc_suffix(code)}.md'

    def sub(m):
        key, flt = m.group(1), m.group(2)
        if key not in v: raise KeyError(f'{src}: missing "{key}"')
        return attr(v[key]) if flt == 'attr' else v[key]
    out = re.sub(r'\{\{(\w+)(?:\|(\w+))?\}\}', sub, tpl)
    if '{{' in out: raise ValueError(f'{src}: unresolved placeholder')
    return out


def lang_links(code, indent):
    cur = ' aria-current="page"'
    return '\n'.join(f'{" " * indent}<li><a href="{page_href(l[1])}" hreflang="{l[3]}" lang="{l[2]}" data-lang="{l[1]}"'
                     f'{cur if l[1] == code else ""}>{l[6]}</a></li>' for l in LANGS)


def lineup_item(art, label):
    w = 300 if art == 'ac' else 240
    return (f'        <li><span class="art"><picture><source srcset="{CDN}/art/{art}-dark.webp" media="(prefers-color-scheme: dark)">'
            f'<img src="{CDN}/art/{art}-light.webp" alt="" width="{w}" height="136" loading="lazy" decoding="async"></picture></span>'
            f'<span>{label}</span></li>')


def redirect_script():
    files = {l[1]: page_file(l[1]) for l in LANGS}
    # 根页面：?lang= > 用户在菜单里选过的语言 > 浏览器语言；只在根页面跳转，各语言页面的链接始终有效
    return ('<script>(function(){try{var F=' + json.dumps(files, separators=(',', ':')) + ';'
            # 繁体中文页面没有发布时，所有中文都去简体页面
            'function pick(x){x=String(x||"").toLowerCase();var c=x.indexOf("zh")===0?(/hant|tw|hk|mo/.test(x)&&F["zh-TW"]?"zh-TW":"zh-CN"):x.split("-")[0];'
            'return F[c]?c:null}'
            'var q=new URLSearchParams(location.search).get("lang"),t=q?pick(q):null;'
            'if(!t){try{t=localStorage.getItem("mijiabar.lang")}catch(e){}if(!F[t])t=null}'
            'if(!t){var ls=navigator.languages||[navigator.language];for(var i=0;i<ls.length&&!t;i++)t=pick(ls[i])}'
            'if(t&&t!=="en")location.replace(F[t]+location.hash)}catch(e){}})()</script>')


def main():
    check = '--check' in sys.argv
    tpl = open('site/template.html', encoding='utf-8').read()
    en = json.load(open('i18n/site/en.json', encoding='utf-8'))
    used = set(re.findall(r'\{\{(\w+)', tpl)) | {'hero_fine', 'final_fine', 'menubar'} | {k for _, k in LINEUP} \
        | {f'{c}{i}' for c in 'qa' for i in range(1, FAQ + 1)}
    unused = sorted(set(en) - used)
    if unused: print('⚠️  en.json 里没用到的键：' + ', '.join(unused))
    prompts, ver, bad, stale = swift_prompts(), version(), False, []
    for lang in LANGS:
        s = json.load(open(f'i18n/site/{lang[0]}.json', encoding='utf-8'))
        missing, extra = [k for k in en if k not in s], [k for k in s if k not in en]
        if missing: print(f'❌ {lang[0]}.json 缺少：' + ', '.join(missing)); bad = True; continue
        if extra: print(f'⚠️  {lang[0]}.json 多出：' + ', '.join(extra))
        mismatch = [k for k in en if en[k].count('|') != s[k].count('|') or ('{v}' in en[k]) != ('{v}' in s[k])]
        if mismatch: print(f'❌ {lang[0]}.json 的 | 或 {{v}} 与英文不一致：' + ', '.join(mismatch)); bad = True; continue
        out = render(tpl, s, lang, prompts, ver)
        path = 'docs/' + page_file(lang[1])
        old = open(path, encoding='utf-8').read() if os.path.exists(path) else None
        if old != out:
            stale.append(path)
            if not check: open(path, 'w', encoding='utf-8').write(out)
    if bad: sys.exit(1)
    if check and stale: print('❌ 网站需要重新生成：python3 scripts/gen-site.py（' + ', '.join(stale) + '）'); sys.exit(1)
    print(('✅ 网站已是最新' if check else f'✅ 生成 {len(LANGS)} 个页面（版本 {ver}）'))


if __name__ == '__main__':
    main()
