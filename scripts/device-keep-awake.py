#!/usr/bin/env python3
"""Hold/release HarmonyOS's system screen lock for an explicitly selected test device."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys


def hdc(*args):
    binary = shutil.which('hdc')
    if not binary:
        bundled = Path('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
        if bundled.is_file():
            binary = str(bundled)
    if not binary:
        raise RuntimeError('找不到 hdc，请先配置 DevEco SDK 的 toolchains 路径')
    result = subprocess.run([binary, *args], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(f'hdc 命令失败（{result.returncode}），请检查设备连接')
    return result.stdout


def select_device(requested=None):
    targets = [line.strip() for line in hdc('list', 'targets').splitlines()
               if re.fullmatch(r'[A-Za-z0-9._:-]+', line.strip()) and not line.startswith('-')]
    if requested:
        if requested not in targets:
            raise RuntimeError('指定设备未连接，未修改任何设备')
        return requested
    if len(targets) != 1:
        raise RuntimeError('需要且只能有一台设备；多设备时请用 --device 指定')
    return targets[0]


def parse_status(power, locks):
    state = re.search(r'Current State:\s*([A-Z_]+)', power)
    timeout = re.search(r'ScreenOffTime:\s*Timeout=(-?\d+)ms', power)
    if not state or not timeout or 'RUNNING LOCK DUMP:' not in locks:
        raise RuntimeError('无法读取此固件的电源状态，未确认常亮状态')
    states = re.findall(r'\bname=PowerMgrKeepOnLock\b[^\n]*\bstate=(\d+)', locks)
    if any(value not in ('0', '1') for value in states):
        raise RuntimeError('系统常亮锁处于未知状态，请人工检查')
    return {'enabled': '1' in states, 'power': state.group(1), 'timeout_ms': int(timeout.group(1))}


def status(device):
    prefix = ('-t', device, 'shell', 'hidumper', '-s', 'PowerManagerService', '-a')
    return parse_status(hdc(*prefix, '-s'), hdc(*prefix, '-r'))


def change(device, action):
    before = status(device)
    if action == 'status':
        return before
    desired = action == 'on'
    if before['enabled'] != desired:
        hdc('-t', device, 'shell', 'hidumper', '-s', 'PowerManagerService', '-a', '-t' if desired else '-f')
    after = status(device)
    if after['enabled'] != desired:
        raise RuntimeError('设备未确认目标常亮状态；请用 status 检查，不会循环重试')
    return after


def main():
    parser = argparse.ArgumentParser(description='调试设备系统常亮；不解锁屏幕、不修改锁屏密码或持久熄屏时间。')
    parser.add_argument('action', choices=['on', 'off', 'status'])
    parser.add_argument('--device', help='HDC 设备 ID；不传时要求只连接一台设备')
    args = parser.parse_args()
    try:
        device = select_device(args.device)
        result = change(device, args.action)
        print(f"设备：{device}\n系统常亮：{'已启用' if result['enabled'] else '已关闭'}\n电源状态：{result['power']}\n自动熄屏配置：{result['timeout_ms']} ms")
        if args.action == 'on':
            print('常亮锁由系统持有，应用退出或重装不会释放。按电源键仍可锁屏；设备重启后请重新检查。')
        return 0
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, RuntimeError) else '设备命令超时，请检查连接后用 status 核对', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
