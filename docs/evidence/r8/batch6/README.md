# R6–R8 第六批联合验收

日期：2026-11-19。隔离服务 T3 0.1.10，Harmony 真机 Mate60Pro，Android Emulator Pixel 6 / API30。未操作真实业务仓库。

## 构建与测试

- 签名 HAP 构建、覆盖安装及启动成功，见 [构建回读](build-readback.json)。宿主测试 339/339 通过，无失败或跳过。
- 系统常亮脚本另有 4 项 Python 测试通过；当前按用户要求保持开启。退出应用、覆盖安装后仍持锁，原 10 分钟熄屏配置未改变，见 [回读](keep-awake-readback.json) 和 [使用方法](../../../device-keep-awake.md)。

## 实际通过的路径

| 功能 | 证据与范围 |
|---|---|
| Android 竖屏操作 | 原生 H.264 画面上点击、拖动、文字输入、Back/Home/最近任务；[返回设置](android-main.jpeg)、[输入 battery](android-input.jpeg)、[拖动结果](android-drag.jpeg)、[最近任务](android-recents.jpeg) |
| 定时任务 | 新建默认停用，编辑为 2050 年单次任务，启用/停用并数据库回读；删除取消保留、确认后恢复原空表；全程运行次数 0。[启用记录](schedule-enabled.json)、[初始](schedules-before.json)、[最终](schedules-after.json)、[清理后界面](schedules-clean.jpeg) |
| 用量 | 当前服务真实汇总、账号与日趋势可读；不保存或公布实际账户费用及 token 数。跨环境去重和价格编辑仍未完成 |
| 普通文件分享 | 修复下载误用预览资源；API 验证 README 80 字节与哈希，临时会话已撤销，见 [回读](download-readback.json)。手机系统分享面板正确显示 README.md，随后取消，未发给其他应用 |
| 缓存归属 | 新分享文件登记当前环境，按环境显示 1 个 80 字节文件；一小时内不可清除。旧未知环境文件未动，见 [范围与保护](cache-scoped.jpeg)。手机实际删除尚未验证 |

## 未通过及证据解释

- 当前服务旋转命令在 Android11 返回 `Unknown command: user-rotation`；[旋转页面](android-landscape.jpeg) 是失败证据。
- 自有无权限动画测试 APK 切横屏后，设备实际尺寸变为 2400×1080，但预览仍为 576×1280 并侧倒；[横屏画面](fixture-landscape.jpeg)、[投影回读](device-projection.json)。接口 pose 为 null，横屏点击未命中计数器，不能宣称横屏控制可用。
- 仅确认竖屏操作；不通过猜测旋转角度补偿触摸，不修改已安装服务端。测试 APK 源码和构建说明在 [android-fixture](android-fixture/README.md)。
- `android-back.jpeg` 抓取早于画面稳定；返回结果使用 android-main.jpeg。`schedule-form.jpeg` 是选择框文字修复前记录，不作为最终视觉通过证据。
- iOS 宿主、实体键盘、完整无障碍/平板/折叠与长时性能仍未验。完整范围见 [收口清单](../../../r6-r8-acceptance.md)。
