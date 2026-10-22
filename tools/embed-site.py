#!/usr/bin/env python3
"""Встраивает сайт из sites/<имя>/ в install.sh как функцию write_html_<имя>().

    python3 tools/embed-site.py mona

Текстовые файлы пишутся через heredoc с одинарными кавычками (без раскрытия $ и `), бинарные (png/ico) — через base64.
Блок между маркерами `# >>> SITE-<имя> BEGIN/END` заменяется при каждом запуске, поэтому команду можно повторять после правки сайта.
"""
import base64, os, re, sys

name = sys.argv[1] if len(sys.argv) > 1 else 'mona'
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
site = os.path.join(root, 'sites', name)
script = os.path.join(root, 'install.sh')
BIN = ('.png', '.ico')

files = []
for dp, _, fs in os.walk(site):
    for f in fs:
        files.append(os.path.relpath(os.path.join(dp, f), site))
files.sort()

dirs = sorted({os.path.dirname(f) for f in files if os.path.dirname(f)})
out = [f'# >>> SITE-{name} BEGIN (сгенерировано tools/embed-site.py, не править руками — правьте sites/{name}/)',
       f'write_html_{name}() {{',
       '    mkdir -p "${WEBROOT}"' + ''.join(f' "${{WEBROOT}}/{d}"' for d in dirs)]
for f in files:
    tag = 'EOF_' + re.sub(r'[^A-Z0-9]', '_', f.upper())
    data = open(os.path.join(site, f), 'rb').read()
    if f.endswith(BIN):
        out.append(f'base64 -d > "${{WEBROOT}}/{f}" <<\'{tag}\'')
        b = base64.b64encode(data).decode()
        out += [b[i:i + 76] for i in range(0, len(b), 76)]
    else:
        txt = data.decode('utf-8')
        assert tag not in txt, f'маркер heredoc {tag} встречается в {f}'
        out.append(f'cat > "${{WEBROOT}}/{f}" <<\'{tag}\'')
        out.append(txt.rstrip('\n'))
    out.append(tag)
out += ['}', f'# <<< SITE-{name} END', '']
block = '\n'.join(out)

src = open(script, encoding='utf-8').read()
pat = re.compile(rf'# >>> SITE-{name} BEGIN.*?# <<< SITE-{name} END\n', re.S)
if pat.search(src):
    src = pat.sub(lambda m: block, src, count=1)
else:
    anchor = 'write_shared_nginx() {'
    assert anchor in src, 'не нашёл место вставки'
    src = src.replace(anchor, block + '\n' + anchor, 1)
open(script, 'w', encoding='utf-8').write(src)
print(f'встроено файлов: {len(files)}, строк блока: {len(out)}')
