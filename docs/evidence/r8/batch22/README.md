# 第二十二批：工作树分支命名

424/424回归、签名构建安装通过，见build.json。扩展branchNamingMode static/semantic/custom、branchNamePrefix、branchNameInstructions，复用身份/权限/fresh policy/单字段patch/写后回读，模式切换保留隐藏字段。组织锁按父子路径处理，原remote/submodules兼容。

真机原static前缀t3，切换semantic保存回读仅出现branchNamingMode:semantic，随后恢复static，原前缀t3仍显示，服务配置相关字段与测试前完全一致，见naming-before/edited/restored.json。naming.jpeg已视觉检查，滚动可达。未创建分支/工作树，未执行清理。

前缀实际修改、自定义多行说明、项目覆盖与组织锁真机仍需补验。目录及清理规则留待后续：worktreesDirectory能力/全局字段；storageCleanup六项与项目worktreeCleanup的inherit/off/custom优先级，不以本批命名设置替代完整S09。

## 固定前缀写回补验

真机将t3改为r22-check并保存，服务端仅branchNamePrefix变化；恢复t3后配置与原快照完全一致，见prefix-edited.json/prefix-restored.json。未创建分支、工作树或运行任务。此结果证明前缀保存，不替代真实生成分支名与项目覆盖矩阵。
