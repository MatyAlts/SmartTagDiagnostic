import plistlib
import tempfile
import unittest
from pathlib import Path
from verify_project import inspect_plist


class ConfigurationSafetyTests(unittest.TestCase):
    def check_plist(self, values):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Info.plist'
            path.write_bytes(plistlib.dumps(values))
            return inspect_plist(path)

    def test_missing_bluetooth_purpose_is_rejected(self):
        errors = self.check_plist({'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}]})
        self.assertIn('Bluetooth permission explanation is missing', errors)

    def test_background_bluetooth_is_rejected(self):
        errors = self.check_plist({
            'NSBluetoothAlwaysUsageDescription': 'Read owned tag battery',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}],
            'UIBackgroundModes': ['bluetooth-central']})
        self.assertIn('Background operation is outside diagnostic scope', errors)

    def test_minimal_scoped_configuration_is_accepted(self):
        errors = self.check_plist({
            'NSBluetoothAlwaysUsageDescription': 'Read owned tag battery',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}]})
        self.assertEqual([], errors)


if __name__ == '__main__':
    unittest.main()
