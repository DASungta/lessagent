import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
export const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') +
  '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
export const data = value => 'data:text/javascript;base64,' + Buffer.from(value).toString('base64');
export const compile = source => ts.transpileModule(source,
  { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
const wire = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const source = (await readFile(new URL('../entry/src/main/ets/protocol/Projects.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wire));
export const projectsUrl = data(compile(source));
