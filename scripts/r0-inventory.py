#!/usr/bin/env python3
"""Rebuild the R0 source ledger from the pinned archive; never executes upstream code."""
import hashlib, json, re, tarfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/r0'
ARCHIVE = ROOT / 'docs/baselines/t3code-ad1b136.tar.gz'
SHA = 'ad1b1365999c92c3fc7a054e7f3af84623f74fee'
assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == '595b64affe9ae78510bbfdcd1cb4f282cade542aa4f8f7c704ea02998321e30a', 'Pinned archive changed'
patterns = {
 'actions': r'\b(?:title|label|accessibilityLabel|id)\s*[:=]|\bon(?:Press|Select|Action|Confirm|Submit|LongPress|Swipe)\w*\s*[:=]|case ["\']',
 'conditions': r'permissionAtom|capabilit|hasCloudPublicConfig|__DEV__|Platform\.OS|isSignedIn|disabled[=:]|enabled[=:]|managedPolicy|supports[A-Z]',
 'calls': r'\b(?:serverEnvironment|projectEnvironment|threadEnvironment|previewEnvironment|terminalEnvironment|deviceEnvironment|gitEnvironment|pullRequestEnvironment)\.|WS_METHODS\.|Rpc\.make|HttpApiEndpoint\.|dispatchCommand|fetch\(|new WebSocket',
 'settings': r'\b(?:setting|settings|preferences|policy)\b|Settings(?:Row|SwitchRow)|key:|field:',
 'native': r'(?:from|import\()\s*["\'](?:expo[^"\']*|react-native[^"\']*|@clerk/[^"\']*|@t3tools/mobile[^"\']*)|requireNativeModule|requireNativeView|registerWebModule',
}
files = {}; ledger = {k: [] for k in patterns}; manifests = []
with tarfile.open(ARCHIVE) as tar:
 for member in tar:
  if not member.isfile(): continue
  path = member.name.split('/', 1)[1]
  data = tar.extractfile(member).read()
  manifests.append({'path': path, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
  if path.endswith(('.ts','.tsx','.json','.cjs','.swift','.kt','.h','.cpp','.md')) and (path.startswith(('apps/mobile/', 'packages/contracts/', 'packages/client-runtime/', 'packages/shared/'))):
   files[path] = data.decode('utf-8', errors='replace')
for path, source in sorted(files.items()):
 if re.search(r'(?:\.test\.|/__tests__/|/nitrogen/|/generated/)', path): continue
 for n, line in enumerate(source.splitlines(), 1):
  for kind, pattern in patterns.items():
   if kind == 'settings' and not ('settings' in path.lower() or 'preferences' in path): continue
   if re.search(pattern, line, re.I if kind == 'conditions' else 0):
    ledger[kind].append({'file': path, 'line': n, 'source': line.strip()})
stack = files['apps/mobile/src/Stack.tsx']
imports = {}
for m in re.finditer(r'import\s+([^;]+?)\s+from\s+["\'](\./[^"\']+)["\'];', stack, re.S):
 for symbol in re.findall(r'\b\w+\b', m[1]): imports[symbol] = 'apps/mobile/src/' + m[2][2:]
routes = []
for m in re.finditer(r'\b(\w+): createNativeStackScreen\(\{', stack):
 start = m.end(); cursor = start; depth = 1
 # Ignore strings/comments while balancing the registration object, including nested options.
 token = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`|//[^\n]*|/\*.*?\*/|[{}]', re.S)
 for part in token.finditer(stack, start):
  if part[0] == '{': depth += 1
  elif part[0] == '}': depth -= 1
  if depth == 0:
   cursor = part.start(); break
 assert depth == 0, m[1]
 block = stack[start:cursor]
 assert len(re.findall(r'\bscreen:', block)) == 1, m[1]
 screen = re.search(r'screen: (\w+)',block)
 assert screen, m[1]
 dest = imports.get(screen[1])
 if dest:
  dest = next((dest+x for x in ('.tsx','.ts') if dest+x in files),dest)
 routes.append({'name':m[1], 'line':stack[:m.start()].count('\n')+1,'screen':screen[1], 'file':dest,'registration':block.strip()})
assert len(routes) == len(re.findall(r': createNativeStackScreen\(', stack))
assert len({r['name'] for r in routes}) == len(routes)
assert all(r['file'] in files or r['name']=='NotFound' for r in routes)
assert 'unsupported' in files['apps/mobile/src/connection/platform.ts']
manifest = {'commit':SHA,'repository':'https://github.com/DASungta/t3code','archive':str(ARCHIVE.relative_to(ROOT)), 'archive_sha256':hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(), 'files':sorted(manifests,key=lambda x:x['path'])}
OUT.mkdir(parents=True,exist_ok=True)
for name,value in [('baseline',manifest),('routes',routes),*ledger.items()]:
 (OUT/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
modules = sorted({p.split('/')[3] for p in files if p.startswith('apps/mobile/modules/')})
(OUT/'native-modules.json').write_text(json.dumps(modules,indent=2)+'\n')

# Preserve the complete capability declaration and wire method catalog separately from call sites.
def source_rows(path, pattern):
 return [{'file': path, 'line': n, 'source': line.strip()} for n, line in enumerate(files[path].splitlines(), 1) if re.search(pattern, line)]
capability_path = 'packages/contracts/src/environment.ts'
cap_block = files[capability_path].split('export const ExecutionEnvironmentCapabilities = Schema.Struct({', 1)[1].split('export const ExecutionEnvironmentDescriptor', 1)[0]
capabilities = []
for match in re.finditer(r'^  (\w+):', cap_block, re.M):
 symbol = match[1]
 declaration = next(row for row in source_rows(capability_path, r'^  '+symbol+r':'))
 refs = [{'file': path, 'line': n, 'source': line.strip()} for path, content in sorted(files.items()) if path.startswith('apps/mobile/src/') and '.test.' not in path for n, line in enumerate(content.splitlines(),1) if re.search(r'\b'+symbol+r'\b', line)]
 capabilities.append({'name':symbol, 'declaration':declaration, 'mobileReferences':refs})
rpc_path = 'packages/contracts/src/rpc.ts'
rpc_text = files[rpc_path]
method_block = rpc_text.split('export const WS_METHODS = {',1)[1].split('} as const',1)[0]
methods = []
for match in re.finditer(r'^  (\w+): "([^"]+)"', method_block, re.M):
 symbol, wire = match.groups()
 refs = source_rows(rpc_path, r'WS_METHODS\.'+symbol+r'\b')
 methods.append({'symbol':symbol, 'wire':wire, 'declaration':source_rows(rpc_path,r'^  '+symbol+r':')[0], 'schemaBindings':refs,
 'permissionReferences':source_rows('packages/contracts/src/clientRpcPermissions.ts',r'WS_METHODS\.'+symbol+r'\b')})
assert len(methods) > 100
controls = []
for path in sorted(files):
 if not path.startswith('apps/mobile/src/features/settings/') or '.test.' in path: continue
 controls += source_rows(path, r'\b(?:title|label|setting|value|onValueChange|onChange|disabled|options|selected)[=:]')
for name, value in [('capabilities',capabilities),('rpc-methods',methods),('settings-controls',controls)]:
 (OUT/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

# Complete route registration ledger, with inline options to retain presentation and aliases.
lines=['# R0 注册路由逐项台账','',f'基线 `{SHA}`；共 {len(routes)} 个 createNativeStackScreen 注册。由 `scripts/r0-inventory.py` 从归档生成。', '', '每项为源码证据 S，真实页面证据均待取得。页面动作/条件/契约/验收见能力矩阵对应组；无独立 URL 的 sheet 同样迁移。ArkUI 使用 Navigation/NavDestination 对应 page，bindSheet 对应 sheet，沉浸全屏对应 immersive；保持原返回栈和参数环境范围。Settings 别名必须保留，ComponentCatalog 仅开发构建，NotFound 保留错误返回。', '', '| 路由 | Stack 行 | 页面源文件 | 注册参数与呈现 |','|---|---:|---|---|']
for r in routes:
 options=' '.join(r['registration'].split()).replace('|','\\|')
 lines.append(f"| {r['name']} | {r['line']} | `{r['file'] or 'Stack.tsx 内联'}` / {r['screen']} | `{options}` |")
(ROOT/'docs/r0-route-ledger.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({'routes':len(routes),'files':len(manifests),'modules':modules,'evidence_lines':{k:len(v) for k,v in ledger.items()},'archive_sha256':manifest['archive_sha256']},ensure_ascii=False,indent=2))
