import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
export const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') + '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
export const compile = source => ts.transpileModule(source,
  { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
export const data = value => 'data:text/javascript;base64,' + Buffer.from(value).toString('base64');
const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const projectsSource = (await readFile(new URL('../entry/src/main/ets/protocol/Projects.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const projectsUrl = data(compile(projectsSource));
const source = (await readFile(new URL('../entry/src/main/ets/protocol/Core.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl))
  .replace("'./Projects'", JSON.stringify(projectsUrl));
export const coreUrl = data(compile(source));

const composerSource = (await readFile(new URL('../entry/src/main/ets/protocol/Composer.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const composerUrl = data(compile(composerSource));

const r4Source = (await readFile(new URL('../entry/src/main/ets/protocol/R4.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl))
  .replace("'./Composer'", JSON.stringify(composerUrl));
export const r4Url = data(compile(r4Source));

const threadItemsSource = (await readFile(new URL('../entry/src/main/ets/protocol/ThreadItems.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const threadItemsUrl = data(compile(threadItemsSource));

const markdownSource = (await readFile(new URL('../entry/src/main/ets/protocol/Markdown.ts', import.meta.url), 'utf8'));
export const markdownUrl = data(compile(markdownSource));

const mermaidSource = (await readFile(new URL('../entry/src/main/ets/protocol/Mermaid.ts', import.meta.url), 'utf8'));
export const mermaidUrl = data(compile(mermaidSource));

const filesSource = (await readFile(new URL('../entry/src/main/ets/protocol/Files.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const filesUrl = data(compile(filesSource));

const r5Source = (await readFile(new URL('../entry/src/main/ets/protocol/R5.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const r5Url = data(compile(r5Source));

const floatingStatusSource = (await readFile(new URL('../entry/src/main/ets/protocol/FloatingStatus.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl))
  .replace("'./Projects'", JSON.stringify(projectsUrl))
  .replace("'./R4'", JSON.stringify(r4Url));
export const floatingStatusUrl = data(compile(floatingStatusSource));

const threadReposSource = (await readFile(new URL('../entry/src/main/ets/protocol/ThreadRepositories.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl))
  .replace("'./Projects'", JSON.stringify(projectsUrl));
export const threadRepositoriesUrl = data(compile(threadReposSource));


const linkedThreadSource = (await readFile(new URL('../entry/src/main/ets/protocol/LinkedThread.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const linkedThreadUrl = data(compile(linkedThreadSource));

const sideThreadSource = (await readFile(new URL('../entry/src/main/ets/protocol/SideThread.ts', import.meta.url), 'utf8'))
  .replace("'./Projects'", JSON.stringify(projectsUrl));
export const sideThreadUrl = data(compile(sideThreadSource));

const linkBatchSource = (await readFile(new URL('../entry/src/main/ets/protocol/LinkBatch.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
export const linkBatchUrl = data(compile(linkBatchSource));