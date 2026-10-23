"""Portable configuration checks; does not compile Swift or prove interoperability."""
import plistlib
import re
import sys
import zipfile
from pathlib import Path


def inspect_target_types(spec):
    # The diagnostic has only these product types; XcodeGen calls unit tests
    # bundle.unit-test, while UI tests use the distinct bundle.ui-testing name.
    supported = {'application', 'bundle.unit-test', 'bundle.ui-testing'}
    product_types = re.findall(r'^\s+type:\s*(\S+)\s*$', spec, re.MULTILINE)
    return ['Unsupported diagnostic target type: ' + product_type
            for product_type in product_types if product_type not in supported]


def inspect_plist(path):
    return inspect_metadata(plistlib.loads(path.read_bytes()))


def inspect_metadata(info):
    errors = []
    if not info.get('NSBluetoothAlwaysUsageDescription', '').strip():
        errors.append('Bluetooth permission explanation is missing')
    schemes = [scheme for entry in info.get('CFBundleURLTypes', [])
               for scheme in entry.get('CFBundleURLSchemes', [])]
    if 'ms-app' not in schemes:
        errors.append('Account callback scheme is missing')
    if info.get('UIBackgroundModes'):
        errors.append('Background operation is outside diagnostic scope')
    if not isinstance(info.get('UILaunchScreen'), dict):
        errors.append('Native launch screen configuration is missing')
    return errors


def inspect_artifact(path):
    if path.suffix.lower() == '.ipa':
        with zipfile.ZipFile(path) as archive:
            info = plistlib.loads(archive.read('Payload/SmartTagDiagnostic.app/Info.plist'))
    else:
        info = plistlib.loads((path / 'Info.plist').read_bytes())
    errors = inspect_metadata(info)
    if info.get('UIDeviceFamily') != [1]:
        errors.append('Diagnostic must target iPhone only')
    if info.get('CFBundleIdentifier') != 'org.local.SmartTagDiagnostic':
        errors.append('Unexpected diagnostic bundle identifier')
    return errors


def main():
    if len(sys.argv) > 1:
        artifact = Path(sys.argv[1])
        errors = inspect_artifact(artifact)
        if errors:
            raise SystemExit('\n'.join(errors))
        print('PASS: built app launch configuration, iPhone family, Bluetooth privacy and callback.')
        return
    root = Path(__file__).resolve().parents[1]
    errors = inspect_plist(root / 'App/Info.plist')
    errors.extend(inspect_target_types((root / 'project.yml').read_text(encoding='utf-8')))
    required = ['project.yml', 'Package.swift', 'App/SmartTagDiagnosticApp.swift',
                'App/UI/DiagnosticView.swift', 'Tests/UITests/DiagnosticUITests.swift',
                'Tests/AppTests/AccountSecurityTests.swift',
                '.github/workflows/ios.yml', 'docs/BUILD.md']
    errors.extend('Missing ' + name for name in required if not (root / name).is_file())
    workflow = (root / '.github/workflows/ios.yml').read_text(encoding='utf-8')
    for command in ['swift test', 'xcodegen generate', 'xcodebuild test', 'xcodebuild archive',
                    'CODE_SIGNING_ALLOWED=NO', 'SmartTagDiagnostic-unsigned.ipa']:
        if command not in workflow:
            errors.append('Build pipeline is missing ' + command)
    if errors:
        raise SystemExit('\n'.join(errors))
    print('PASS: plist permissions/callback, source paths and unsigned build stages. Native compile and hardware checks remain pending.')


if __name__ == '__main__':
    main()
