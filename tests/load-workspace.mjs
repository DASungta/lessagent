import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { projectsUrl } from './load-core.mjs';
export const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') +
  '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
export const data = value => 'data:text/javascript;base64,' + Buffer.from(value).toString('base64');
export const compile = source => ts.transpileModule(source,
  { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
const source = (await readFile(new URL('../entry/src/main/ets/services/Workspace.ets', import.meta.url), 'utf8'))
  .replace("import { util } from '@kit.ArkTS';", 'const util = globalThis.__workspaceKit.util;')
  .replace("'../protocol/Projects'", JSON.stringify(projectsUrl));
export const workspaceUrl = data(compile(source));
