"""Portable configuration checks; does not compile Swift or prove interoperability."""
import plistlib
from pathlib import Path


def inspect_plist(path):
    info = plistlib.loads(path.read_bytes())
    errors = []
    if not info.get('NSBluetoothAlwaysUsageDescription', '').strip():
        errors.append('Bluetooth permission explanation is missing')
    schemes = [scheme for entry in info.get('CFBundleURLTypes', [])
               for scheme in entry.get('CFBundleURLSchemes', [])]
    if 'ms-app' not in schemes:
        errors.append('Account callback scheme is missing')
    if info.get('UIBackgroundModes'):
        errors.append('Background operation is outside diagnostic scope')
    return errors


def main():
    root = Path(__file__).resolve().parents[1]
    errors = inspect_plist(root / 'App/Info.plist')
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
