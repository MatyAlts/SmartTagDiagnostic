---
name: SmartTag Diagnostic native iOS
description: Conventional SwiftUI diagnostics using the system visual language
---

# Design System: SmartTag Diagnostic

## Overview

The confirmed direction is conventional native iOS. SwiftUI supplies navigation, list surfaces, controls and system transitions. This is a native scan of the current source, not a rendered visual audit or a web design system.

Operating mode: owner-operated experimental diagnostics, with account → tag → explicit nearby Bluetooth candidate → test. Technical events have a separate destination. Product scope and interoperability constraints remain in PRODUCT.md.

## Colors

Native semantic tokens are authoritative: the inset grouped List supplies system grouped backgrounds and separators; default text uses the system label color, and `.secondary` supplies secondary label styling. These resolve through the platform rather than fixed CSS or hex values. Interactive tint is SwiftUI `.blue`; inline error text uses `.red`. Appearance and contrast remain unverified.

## Typography

Use the system San Francisco family through SwiftUI text styles and default control typography, allowing Dynamic Type. The source explicitly uses `.caption` for signal strength; other content retains system defaults. Root navigation uses the system title treatment and detail destinations request inline titles. Do not infer custom point sizes or headline styles that are absent from the source.

## Layout

`NavigationStack` contains a `List` with `.insetGrouped` styling and system-managed spacing, safe areas and row geometry. Sections organize account, tag selection, Bluetooth actions and errors. The root title is “Diagnóstico Tag”; the event log and About screen are pushed destinations. No custom layout grid or measured spacing scale is established.

Every interactive target should be at least 44 × 44 pt. This is a design requirement, not an observed measurement; validate row targets on Simulator and hardware, including large Dynamic Type.

## Elevation & Depth

Platform list surfaces and navigation provide grouping and hierarchy. The source defines no custom shadows, blur materials or animations; preserve system transitions and verify Reduce Motion behavior.

## Shapes

The system controls inset grouped row shape and control geometry. No app-specific corner-radius or border tokens are established.

## Components

Use native `Button`, `Label`, `ProgressView`, `NavigationLink` and `LabeledContent`, with SF Symbols (`person.crop.circle`, `tag`, `checkmark`) for existing iconography. Busy and unavailable actions use native disabled states. Selected rows show a checkmark, progress stays inline, and errors include an accessibility label. The selected account tag checkmark uses “Seleccionada”; the nearby-candidate checkmark uses “Periférico seleccionado”. VoiceOver announcements remain pending runtime verification.

`batteryResult` is the source's explicit accessibility identifier, attached to the battery result. It is an automation hook, not evidence of VoiceOver correctness. No additional accessibility identifiers were observed in this view.

## Do's and Don'ts

- Do retain system navigation, semantic foreground/background behavior, SF Symbols and Dynamic Type.
- Do preserve separate user actions for scanning, candidate selection and authentication.
- Do verify light and dark appearances, large Dynamic Type, truncation, contrast, VoiceOver selection announcements, touch targets and Reduce Motion on native runtime evidence.
- Don't claim visual or accessibility passes from source inspection. Windows has no Swift/Xcode Simulator or captured native screenshots here; native build, visual and hardware checks remain pending.
- Don't synthesize HTML/CSS previews, web tokens, fabricated screenshots or unofficial Samsung branding for this native system.
