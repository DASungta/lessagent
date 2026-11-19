import importlib.util
import pathlib
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('keep_awake', pathlib.Path(__file__).parents[1] / 'scripts/device-keep-awake.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
POWER = 'Current State: AWAKE Reason: 34\nScreenOffTime: Timeout=600000ms\n'

def locks(state):
    return 'RUNNING LOCK DUMP:\nname=AnotherScreenLock state=1\nname=PowerMgrKeepOnLock uid=5528 pid=1453 state=' + str(state)

class KeepAwakeTests(unittest.TestCase):
    def test_status_only_uses_own_named_system_lock(self):
        self.assertFalse(mod.parse_status(POWER, locks(0))['enabled'])
        self.assertTrue(mod.parse_status(POWER, locks(1))['enabled'])
        self.assertEqual(mod.parse_status(POWER, locks(1))['timeout_ms'], 600000)
        with self.assertRaises(RuntimeError): mod.parse_status('bad', locks(1))
        with self.assertRaises(RuntimeError): mod.parse_status(POWER, locks(2))
    def test_no_ambiguous_device_mutation(self):
        with patch.object(mod, 'hdc', return_value='first\nsecond\n'):
            with self.assertRaises(RuntimeError): mod.select_device()
            self.assertEqual(mod.select_device('second'), 'second')
            with self.assertRaises(RuntimeError): mod.select_device('missing')
        with patch.object(mod, 'hdc', return_value='[Empty]\n'):
            with self.assertRaises(RuntimeError): mod.select_device()
    def test_enable_disable_and_idempotence(self):
        for action, before, after, flag in [('on', False, True, '-t'), ('off', True, False, '-f')]:
            with patch.object(mod, 'status', side_effect=[{'enabled':before},{'enabled':after}]), patch.object(mod,'hdc') as command:
                self.assertEqual(mod.change('device',action)['enabled'],after)
                command.assert_called_once_with('-t','device','shell','hidumper','-s','PowerManagerService','-a',flag)
        with patch.object(mod,'status',return_value={'enabled':True}),patch.object(mod,'hdc') as command:
            mod.change('device','on');command.assert_not_called()
    def test_failed_readback_never_reports_success(self):
        with patch.object(mod,'status',return_value={'enabled':False}),patch.object(mod,'hdc'):
            with self.assertRaises(RuntimeError): mod.change('device','on')

if __name__ == '__main__': unittest.main()
