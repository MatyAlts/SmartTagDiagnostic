import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from verify_project import inspect_plist, inspect_target_types, inspect_artifact


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
            'NSNearbyInteractionUsageDescription': 'Measure distance to an owned tag',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}],
            'UILaunchScreen': {}})
        self.assertEqual([], errors)

    def test_missing_nearby_interaction_purpose_is_rejected(self):
        values = {
            'CFBundleIdentifier': 'org.local.SmartTagDiagnostic',
            'NSBluetoothAlwaysUsageDescription': 'Read owned tag battery',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}],
            'UILaunchScreen': {}, 'UIDeviceFamily': [1]}
        self.assertEqual(['Nearby Interaction permission explanation is missing'],
                         self.check_plist(values))
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'SmartTagDiagnostic.app'
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps(values))
            self.assertEqual(['Nearby Interaction permission explanation is missing'],
                             inspect_artifact(app))

    def test_blank_nearby_interaction_purpose_is_rejected(self):
        values = {
            'NSBluetoothAlwaysUsageDescription': 'Read owned tag battery',
            'NSNearbyInteractionUsageDescription': '  \n\t',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}],
            'UILaunchScreen': {}}
        self.assertEqual(['Nearby Interaction permission explanation is missing'],
                         self.check_plist(values))

    def test_missing_launch_configuration_is_rejected(self):
        errors = self.check_plist({
            'NSBluetoothAlwaysUsageDescription': 'Read owned tag battery',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}]})
        self.assertIn('Native launch screen configuration is missing', errors)

    def test_packaged_plist_preserves_launch_privacy_and_callback(self):
        values = {
            'CFBundleIdentifier': 'org.local.SmartTagDiagnostic',
            'NSBluetoothAlwaysUsageDescription': 'Read owned tag battery',
            'NSNearbyInteractionUsageDescription': 'Measure distance to an owned tag',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['ms-app']}],
            'UILaunchScreen': {}, 'UIDeviceFamily': [1]}
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'SmartTagDiagnostic.app'
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps(values))
            self.assertEqual([], inspect_artifact(app))
            ipa = Path(directory) / 'diagnostic.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/SmartTagDiagnostic.app/Info.plist', plistlib.dumps(values))
            self.assertEqual([], inspect_artifact(ipa))

    def test_old_generated_ipa_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'diagnostic.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/SmartTagDiagnostic.app/Info.plist', plistlib.dumps({
                    'CFBundleIdentifier': 'org.local.SmartTagDiagnostic',
                    'UIDeviceFamily': [1, 2]}))
            errors = inspect_artifact(ipa)
            self.assertIn('Native launch screen configuration is missing', errors)
            self.assertIn('Bluetooth permission explanation is missing', errors)
            self.assertIn('Account callback scheme is missing', errors)
            self.assertIn('Diagnostic must target iPhone only', errors)

    def test_unrelated_bundle_cannot_pass_artifact_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Other.app'
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'other.application', 'UIDeviceFamily': [1]}))
            self.assertIn('Unexpected diagnostic bundle identifier', inspect_artifact(app))


if __name__ == '__main__':
    unittest.main()
