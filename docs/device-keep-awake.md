# 鸿蒙调试常亮

用于专用 Mate60Pro 的长时间开发验收。脚本调用设备原生 PowerManagerService 的调试常亮锁，由系统持有，不依赖 T3 Harmony 应用进程，也不需要循环点击屏幕。

```sh
python3 scripts/device-keep-awake.py on --device 23E0224122000135
python3 scripts/device-keep-awake.py status --device 23E0224122000135
python3 scripts/device-keep-awake.py off --device 23E0224122000135
```

只连接一台 HDC 设备时可省略 `--device`；多设备时必须指定，脚本不会猜目标。优先使用 PATH 中的 hdc，未找到时尝试本机 DevEco Studio SDK 路径。

- `on`：获取系统 `PowerMgrKeepOnLock`，读取状态确认已启用。
- `status`：只读显示常亮锁、电源状态与自动熄屏配置。
- `off`：释放该调试常亮锁，恢复正常自动熄屏行为。
- 不修改屏幕密码、开发者模式、原熄屏时长或其他应用的运行锁。按电源键仍可锁屏；已锁住的设备仍需手动解锁。设备重启后用 status 检查，必要时再次 on。
- 这是系统级调试锁，不会随测试应用退出而释放；结束调试时主动执行 off。

## 当前设备实测

2026-11-19，设备 `23E0224122000135`：

- 原自动熄屏时间 600000 ms（10分钟）。
- 开启时 `PowerMgrKeepOnLock state=1`，关闭时 state=0；熄屏配置始终 600000 ms。
- 关闭 T3 Harmony 后仍持锁；覆盖安装 HAP、再次关闭并启动应用后仍持锁，应用启动成功。
- 4 项脚本自检通过：状态解析、唯一设备选择、开关幂等、失败回读不假成功。

```sh
python3 tests/device-keep-awake.test.py
```

本次按用户要求保持开启。该结果证明本设备的原生调试常亮锁可用，不承诺所有鸿蒙固件都提供相同 hidumper 接口；接口或状态无法确认时脚本报错，不循环尝试其他控制方式。
