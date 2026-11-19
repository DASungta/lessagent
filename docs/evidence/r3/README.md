# R3 证据索引

日期：2026-11-17。基线：`DASungta/t3code` `ad1b1365999c92c3fc7a054e7f3af84623f74fee`。最终候选安装在专用 `ALN-AL80 / 23E0224122000135`，只使用隔离 T3 0.1.9 服务 `127.0.0.1:47891`。

## 最终产物

- `r3-candidate-signed.hap`：最终普通签名 HAP，已覆盖安装。SHA256 `bf9937b56c35c44ed38c0d6112634bc395e59549548a86969d4ef17ea28c6137`。
- `r3-hap.sha256`：最终 HAP 摘要。
- `r3-final-tests.log`：`node --experimental-strip-types --test tests/*.test.mjs`，**173/173 通过**。
- `r3-final-build.log`：`./scripts/build.sh`，编译、签名、打包成功。
- `r3-local-tests.log`、`r3-build.log`：首轮 170 项测试/构建历史日志，保留不覆盖。
- `pre-r3-source.tar.gz`：修改前 `entry/src/main/ets`、基础颜色资源和历史 README 备份；SHA256 `d558b294073e856109ed081b77194c7d7403c6d5645a5c4af9749cf2e7c17ff6`。
- `pre-r3-docs.tar.gz`：修改前 README、迁移计划、矩阵、路由台账、R1/R2 进展；SHA256 `dd558fd79d6dd72d6ecba3fb5517171f1963cb1904846517665541a52282ad8c`。
- `worktree-files.json`：首轮新增/修改文件清单；最终变更以源码和 `r3-progress.md` 为准。

## 设备与服务证据

- `device/r3-device-verification.json`：设备型号/序列、隔离环境、最终 HAP 摘要、16 项脱敏回读、剩余边界及截图 SHA256。
- `device/r3-cleanup.json`：累计撤销 9 个隔离测试会话、配对码归零、移除设备上的 `47891` 环境、删除 9 个临时凭据文件；保留的两个 R1 环境及 `tcp:3773`/`tcp:47831` reverse。

最终 HAP `bf9937b5...` 已在设备上完成自动 Settle 菜单即时刷新复核；此前系统协同升级导致的重启已恢复并解锁。
- `device/r3-home-shelves.png`：固定/活跃/暂缓/Settled 列表与项目过滤。
- `device/r3-project-picker.png`、`device/r3-add-project-source.png`、`device/r3-new-project.png`：R3 项目选择与来源页。
- `device/r3-new-task-project-selection.png`、`device/r3-clone-success-project.png`：项目选择/克隆成功后的新任务接口衔接。
- `device/r3-clone-cancelled.png`：克隆运行中取消后的原生状态。
- `device/r3-settings.png`、`device/r3-project-overview.png`、`device/r3-archive.png`：设置、项目概览、归档页。
- `device/r3-search-gamma.png`：搜索命中暂缓会话。

## 已回读的真实写操作

- 新建项目、local folder `project-c`、Git URL 克隆成功；本地裸仓库 HEAD `3fb8c4bfab5bf418860d819118670cfe9d524de6` 与目标一致。
- 克隆失败显示重试，`projectClone.retry` 成功发出；慢连接取消显示“已请求取消”，`projectClone.cancel` 成功发出。
- 项目改名、固定/取消、归档/取消、删除确认/取消/确认均读回 DB 字段。
- 会话 Settle/撤销、归档/恢复、上移顺序、暂缓、自动 Settle 暂停/恢复均读回服务端状态。
- 搜索、项目过滤标签和仓库/路径分组切换已在设备操作并回读本机偏好。

## 复核命令

```sh
shasum -a 256 docs/baselines/t3code-ad1b136.tar.gz
node --experimental-strip-types --test tests/*.test.mjs
./scripts/build.sh
shasum -a 256 docs/evidence/r3/r3-candidate-signed.hap
```

## 证据边界

- 173 项是宿主 Node 契约/状态/命令/隔离测试；设备截图和服务 DB 回读才证明对应 UI/写操作，两者不能互相替代。
- 原版 R3 页面视觉逐项对照、最大字体/系统深浅色、运行中归档限制、严格只读/无权限矩阵、拖拽排序、provider 登录/发布/重生成仍未验收。
- 本轮没有对真实工作项目执行删除、克隆、切分支或任务提交；测试项目只在 `/tmp/t3-r3-accept-WuIFKn`。R3 未宣布完整关闭。
