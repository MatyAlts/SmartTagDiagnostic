import plistlib
import tempfile
import unittest
from pathlib import Path
from verify_project import inspect_plist, inspect_target_types


class ConfigurationSafetyTests(unittest.TestCase):
    def test_misspelled_unit_test_product_type_is_rejected(self):
        errors = inspect_target_types('targets:\n  Tests:\n    type: bundle.unit-testing\n')
        self.assertIn('Unsupported diagnostic target type: bundle.unit-testing', errors)

    def test_supported_application_and_test_product_types_are_accepted(self):
        self.assertEqual([], inspect_target_types(
            'targets:\n  App:\n    type: application\n'
            '  Tests:\n    type: bundle.unit-test\n'
            '  UITests:\n    type: bundle.ui-testing\n'))

    def test_repository_target_types_are_supported(self):
        project = Path(__file__).resolve().parents[1] / 'project.yml'
        self.assertEqual([], inspect_target_types(project.read_text(encoding='utf-8')))

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
