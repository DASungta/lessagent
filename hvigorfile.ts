import { hvigor, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

function readEnv(name: string): string {
  const proc = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process;
  return proc?.env?.[name] || '';
}

function releaseSigningPlugin(): HvigorPlugin {
  return {
    pluginId: 't3ReleaseSigningPlugin',
    apply(node: HvigorNode): void {
      const storeFile = readEnv('T3_RELEASE_STORE_FILE');
      const certpath = readEnv('T3_RELEASE_CERT_PATH');
      const profile = readEnv('T3_RELEASE_PROFILE_PATH');
      const keyAlias = readEnv('T3_RELEASE_KEY_ALIAS');
      const storePassword = readEnv('T3_RELEASE_STORE_PASSWORD_ENC');
      const keyPassword = readEnv('T3_RELEASE_KEY_PASSWORD_ENC');
      if (!storeFile || !certpath || !profile || !keyAlias || !storePassword || !keyPassword) {
        return;
      }
      hvigor.nodesEvaluated(() => {
        const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext | undefined;
        if (!appContext) return;
        const opt = appContext.getBuildProfileOpt();
        const signingConfigs = (opt.app.signingConfigs || []).filter((cfg) => cfg.name !== 'release');
        signingConfigs.push({
          name: 'release',
          type: 'HarmonyOS',
          material: {
            storeFile,
            storePassword,
            keyAlias,
            keyPassword,
            signAlg: 'SHA256withECDSA',
            profile,
            certpath
          }
        });
        opt.app.signingConfigs = signingConfigs;
        const products = opt.app.products || [];
        for (const product of products) {
          if (product.name === 'release') {
            product.signingConfig = 'release';
          }
        }
        appContext.setBuildProfileOpt(opt);
      });
    }
  };
}

export default {
  system: appTasks,
  plugins: [releaseSigningPlugin()]
};
