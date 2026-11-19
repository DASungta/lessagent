# Android preview test fixture

独立测试 APK，包名 `com.dasungta.harmony.previewfixture`，启动 Activity 为 `.MainActivity`。不属于产品功能，无网络、文件或其他权限，不持久化测试输入，禁用系统备份。

界面显示实际屏幕像素尺寸、内容区域尺寸、横竖方向和累计动画帧计数。青色圆点和黄色条约每 33 ms 更新一次；该计数是 UI 更新次数，不代表编码器或 Harmony 解码器实际帧率。进入后台时停止更新。按钮计数、单行 EditText 回显与横竖屏按钮用于正式设备链路验收；横竖屏按钮直接调用 `Activity.setRequestedOrientation`，避免依赖系统 shell 旋转命令。旋转时 Activity 重建并恢复计数与文本。

## 离线构建

在此目录执行 `bash build.sh`，无需 Gradle 或下载。默认使用 macOS 本机 Android SDK 的 build-tools 36.0.0、android-37.0 平台及 `java_home` 返回的 JDK；可通过 `ANDROID_SDK_ROOT`、`BUILD_TOOLS_VERSION`、`ANDROID_PLATFORM`、`JAVA_HOME` 指向其他已安装工具。最低 API 23，target API 30。

构建包含源码/清单断言、DEX 打包、签名验证、ZIP 对齐、包名/启动 Activity/无权限/内容校验。一次性签名密钥只保存在权限受限的临时目录，构建结束自动删除，密码不打印、不写入文件。每次构建签名不同，重建 APK 替换旧安装时需要先卸载旧的**测试夹具**；构建流程不执行安装、卸载或任何设备操作。可复现的是构建步骤，随机签名使 APK 字节和 SHA 不固定。

## 设备验收（由主代理通过正式 device 工具执行）

1. 安装并打开 APK，观察 Harmony H264 预览中的尺寸、帧计数及连续动画。
2. 点击计数按钮并输入非敏感测试文本，确认远端与预览回显一致。
3. 收起键盘，点击 Landscape，确认屏幕宽高交换和预览解码重建；再点 Portrait。
4. 切换后台后返回，确认预览恢复且计数连续；重新启动 Activity 不是持久化恢复测试。

未安装/运行或验证实际输入、旋转、后台与 Harmony 解码路径；APK 静态检查不能代替上述设备验收。系统多窗口或方向锁定策略仍可能影响旋转。测试完成后卸载此独立夹具即可。
