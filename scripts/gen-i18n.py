#!/usr/bin/env python3
"""i18n/*.tsv → Sources/MijiaCore/Translations.swift，并检查所有 L()/LF() 英文键是否都有翻译。
TSV 每行：英文键 \t de \t fr \t es \t it \t ru \t ja（简体中文为代码原文，繁体自动转换）"""
import re, glob, os, sys
os.chdir(os.path.join(os.path.dirname(__file__), '..'))
def load(f):
    d = {}
    for line in open('i18n/' + f, encoding='utf-8').read().split('\n'):
        if not line.strip(): continue
        c = line.split('\t'); assert len(c) == 7, (f, line); d[c[0]] = c[1:]
    return d
ui, va, na = load('ui.tsv'), load('values.tsv'), load('names.tsv')
# 繁体（台湾用语）：简体原文 \t 繁体，人工校对
hant = {}
for line in open('i18n/zh-Hant.tsv', encoding='utf-8').read().split('\n'):
    if line.strip(): a, b = line.split('\t'); hant[a] = b
esc = lambda s: s.replace('\\', '\\\\').replace('"', '\\"')
def emit(name, d):
    return '\n'.join([f'public let {name}: [String: [String]] = ['] + ['    "%s": [%s],' % (esc(k), ', '.join('"%s"' % esc(x) for x in v)) for k, v in d.items()] + [']'])
open('Sources/MijiaCore/Translations.swift', 'w', encoding='utf-8').write('''import Foundation

// 由 scripts/gen-i18n.py 从 i18n/*.tsv 生成，请勿手改。顺序：de, fr, es, it, ru, ja。简体为原文、繁体自动转换、英文为键。

extension AppLang {
    /// 在翻译数组中的下标（仅 de/fr/es/it/ru/ja 有效）
    public var trIndex: Int { [.de: 0, .fr: 1, .es: 2, .it: 3, .ru: 4, .ja: 5][self] ?? 0 }
}

/// 按英文原文查找翻译；中文和英文返回 nil
public func tr(_ en: String, _ lang: AppLang) -> String? {
    switch lang { case .zhHans, .zhHant, .en: return nil; default: return uiTable[en]?[lang.trIndex] }
}

''' + emit('uiTable', ui) + '\n\n/// 设备状态取值（键为小写英文）\n' + emit('trValueTable', va) + '\n\n/// MIoT 属性/服务名\n' + emit('trNameTable', na) + '\n\n/// 繁体中文（台湾用语），键为简体原文\npublic let hantTable: [String: String] = [\n' + '\n'.join('    "%s": "%s",' % (esc(k), esc(v)) for k, v in hant.items()) + '\n]\n')
pat = re.compile(r'\bLF?\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"')
miss = {m.group(2).replace('\\"', '"') for f in glob.glob('Sources/**/*.swift', recursive=True) for m in pat.finditer(open(f, encoding='utf-8').read())} - set(ui)
zhk = {m.group(1).replace('\\"', '"') for f in glob.glob('Sources/**/*.swift', recursive=True) for m in pat.finditer(open(f, encoding='utf-8').read())}
miss |= {'[zh-Hant] ' + z for z in zhk - set(hant) if re.search('[\u4e00-\u9fff]', z)}
if miss: print('缺少翻译：', *sorted(miss), sep='\n  '); sys.exit(1)
print(f'✅ {len(ui)} 条界面文案、{len(va)} 个取值、{len(na)} 个属性名，6 种语言全部覆盖；繁体（台湾）{len(hant)} 条')
