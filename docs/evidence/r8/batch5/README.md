# R6–R8 第五批联合验收

2026-11-18 晚至 2026-11-19 凌晨。专用 Mate60Pro `23E0224122000135`，隔离 T3 0.1.10 / r5-round2；远端 Pixel_6_API_30 Android 11 模拟器。317/317 宿主测试通过，CMake/Ninja/native 与签名 HAP 构建成功，最终候选已覆盖安装。包 SHA256 `c3e89c5ca183970fdf09aa1189dfa80e7fd4b6611ad9407d5f0829e66de66375`。未初始化 Git、提交或发布。

## 用户配合的语音成功路径

用户在专用机上允许麦克风并口述，离线识别结果为“请帮我检查这个项目的开发进度。”，结束后页面显示检查文字。父会话点击加入草稿，只进入当前会话输入框；隔离服务消息查询命中0条，未自动发送。voice-recognized.jpeg / voice-draft.jpeg。语音实现仍固定offline、PCM在内存处理，无音频文件归档；本次只归档用户同意测试的通用文字截图。真实成功验证补齐了上一批只有拒绝路径的不足，多语言/音频路由/模型管理仍待补。

## Android 原生 H.264 视频

新增本地NAPI/C++模块、OH_VideoDecoder工作线程、NativeWindow和XComponent。只新增本地类型依赖，ohpm本地解析，无外部下载；HAP包含arm64-v8a libt3device.so及SDK libc++_shared.so。

首轮真机0帧失败证据保留在 android-native-first.jpeg。hilog定位 SetSurface失败，按[华为原生解码顺序](https://developer.huawei.com/consumer/en/doc/HarmonyOS-Guides/video-decoding/)改为Configure→SetSurface→Prepare→Start，并保留阶段/错误码。随后真机12帧、129帧、退出重进48帧，观察丢帧0；模拟器从设置首页切到搜索页时，鸿蒙画面同步变化，见 android-native-fixed / android-native-changed / android-native-reopen。计数来自native输出回调，不是截图轮询。

模拟器由T3 Device/agent-device启动和操作，鸿蒙端仅接收视频。测试范围是只读实时画面，触控/按键/旋转输入、WebRTC及长时性能尚未完成，不称完整设备远控。

三个媒体Panel补后台主动断流/释放；watchdog在owner失效且没有新帧时仍停止native/socket/timer。真机切到系统设置后再回来，画面保持暂停；手动连接重新校验原环境/会话、取得新票据并渲染21帧，见android-background / android-resumed。不会自动重放输入。

## 设备服务设置

隔离环境初始未启用设备支持；新增显式确认入口，device.configure启用后再读清单。只改变隔离服务的enableDeviceSupport与onboarding，Agent访问项保持原值。before JSON与readback.json保留范围；隔离环境保持设备支持启用，方便后续开发，未修改真实环境。设备打开使用服务端返回的实际deviceId，并校验host/thread/platform，避免AVD启动后ID变化。

## Provider、后续消息与键盘

- Provider真实列表/状态/模型目录及刷新通过：Codex已登录、27个模型，provider-models.jpeg / providers.jpeg。没有执行真实登录、登出、安装或卸载；认证挑战路径只有实现和宿主测试。
- 后续消息偏好：选择排队→杀进程/覆盖安装→重新打开仍选排队，followup-restored.jpeg；测试后恢复默认立即引导。自动模式只在已有active run时采用偏好，显式队列/引导覆盖默认，已提交队列不修改。默认steer跟随固定原版，旧偏好文件可兼容读取。
- 键盘命令与帮助页已接：搜索、新任务、返回、Ctrl/Cmd+Enter发送；普通Enter不发送，保护IME组合文本、焦点、忙碌和未知提交。keyboard-help.jpeg只证明入口/说明可见；实体USB/蓝牙键盘与系统保留Cmd键尚未实测。

## 仍未关闭

Android触控/按键/旋转、iOS真实宿主、完整终端/浏览器设备功能；provider完整认证及账号管理、定时任务、用量、更多系统集成设置；实体键盘、读屏、关怀模式更大字体、折叠布局与完整性能/安全/升级矩阵。R6–R8继续推进，不用本批成功路径替代全量验收。
