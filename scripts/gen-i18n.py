#!/usr/bin/env python3
"""i18n/zh-Hant.tsv → Sources/MijiaCore/Translations.swift，并检查所有 L()/LF() 的简体原文都有繁体（台湾用语）。
界面只有三种语言：简体中文为代码原文，English 为 L() 的第二个参数，繁体中文来自 zh-Hant.tsv（每行：简体原文 \t 繁体）。
  python3 scripts/gen-i18n.py --check  # 只检查，不写文件"""
import re, glob, os, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
check = '--check' in sys.argv
hant = {}
for line in open('i18n/zh-Hant.tsv', encoding='utf-8').read().split('\n'):
    if line.strip(): a, b = line.split('\t'); hant[a] = b
esc = lambda s: s.replace('\\', '\\\\').replace('"', '\\"')
out = ('import Foundation\n\n// 由 scripts/gen-i18n.py 从 i18n/zh-Hant.tsv 生成，请勿手改。\n\n'
       '/// 繁体中文（台湾用语），键为简体原文\npublic let hantTable: [String: String] = [\n'
       + '\n'.join('    "%s": "%s",' % (esc(k), esc(v)) for k, v in hant.items()) + '\n]\n')
path = 'Sources/MijiaCore/Translations.swift'
stale = open(path, encoding='utf-8').read() != out if os.path.exists(path) else True
if not check: open(path, 'w', encoding='utf-8').write(out)
pat = re.compile(r'\bLF?\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"')
zhk = {m.group(1).replace('\\"', '"') for f in glob.glob('Sources/**/*.swift', recursive=True) for m in pat.finditer(open(f, encoding='utf-8').read())}
miss = {z for z in zhk - set(hant) if re.search('[\u4e00-\u9fff]', z)}
if miss: print('缺少繁体（台湾用语）翻译，请加到 i18n/zh-Hant.tsv：', *sorted(miss), sep='\n  '); sys.exit(1)
if check and stale: print('❌ Translations.swift 需要重新生成：python3 scripts/gen-i18n.py'); sys.exit(1)
print(f'✅ 繁体（台湾）{len(hant)} 条，所有 L() 文案已覆盖' + ('，Translations.swift 已是最新' if check else ''))
