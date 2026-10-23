# UWB address and hopping requirements

## Intent, evidence and scope
User authorized investigate Apple/Samsung address/UWB requirements, correct supported defects and newIPA2026-10-23, existing MatyAlts gh session for MatyAlts/SmartTagDiagnostic branchpush/Actions/download. NoPR/merge, noownercloud/devicecalls. Baseline388834d source6f18f88; priorGREEN39960653455 106native/12Python. Fresh safetybaseline39964014518 underway before edits.
Owner BaseNIremoval1.784s afterACK vsbothinvertedappdeadline31.116s,0updatesboth, bothnowSTOPACK+cleanclose. No addresscorrectness/radiointeroperability proved. Independent delegated Apple/Samsung research: no new deterministicradiofieldbug established. Apple numericaddressesLE, Samsungopaquearrays remain crossstackuncertainty. FirmwareMACcontrolmessage/headerIErequirements are not established by35byteecho. FullApplePDFunavailable; freshindexedofficialexcerpts+Context7publicAPIused.
AppleR4Table4-2 permitsREQUESTED_HOPPING_MODE0/1; §4.4.3.3 maygrantrequests andreturnsselectedvalue. Boundednewexperiment: v2requestoff changesbootstrapbyte41only; preserve6slots/2400RSTU/240ms, vendor/IV/session/addresses. AlwaysdecodeApple'sselectedflag; ifoffrequestedbutonselected, failbeforeSamsungconfiguration. Baselineonenabledrequestretainscurrentbehavior. No request1.1 experiment, noforcedselectedflag, nolongertimeouts. This is experiment notprovenfix.

## Tasks and routes
- [ ] H1: Add testfirst requestencoding/admission tests, optionaloffrequest UI/NIwiring andsafe requested/selected diagnostics, sourceevidence docs. Delegateddirect4+filemapping/multifilewriter. Defaultunchanged; v1offunsupportedexplicitly, nofalseoffclaim; currentaddressmodefixed. Testsasymmetricpacketvectors, onlybyte41diff, Samsungselectedoffmask4only, failedrequestbeforeBLE. NewtestsREDobservedbeforeproduction. Commitcode+tests+docsoneworkunit.
- [ ] H2: FullGREEN/build/archive/downloadverifyIPA, timestamps+handoff. Inlineorchestration/delegatedfixes asneeded. Native/Python/metadata/CRC/arm64/unsigned/SHA256/capture. PhysicalCleoresultsremainpending.

## Workflow
StrictTDDenableduserAGENTS; native swift test/xcodebuild test macOSActions, Windowsnorunner. Establishbaseline, nativeREDbeforeproduction, thenGREEN/triangulation. RDDdisabled/unmanaged; no reviewrun. Applywork-unit-commits; cachedask-on-risk/stacked-to-main; forecast200-350authoredlinesadvisory, noPR. Rollbackafter388834d removesonlythisfeature. PreserveowneruntrackeddocsZIP/JPGincluding(4).zip. Tracker odd/tasks/uwb-hopping-request.md fullmirrorodd/uwb-hopping-request/tasks projectrea projects. Oldclosedtrackersunchanged.

## Progress
Appleindependentread-onlyauditcompleted; Samsungfocusedcorroborationpending. Baseline39964014518inprogress. No sourcewritestilltracker+mirrorcomplete.

- Samsungcorroborationcomplete: pinneduTagbit34controlsheaderbyte4mask04; disabledFiRaenum/default0 butuTagalwayshopson, firmwareoffacceptanceunknown. AOSP25caf085FiraEncoder426-437 convertsMAC/vendorarraysdifferentlypreAndroid14vs14+, IVunchanged276-280; universalfirmwaremappingunproved. APK11DEXboundedsearchdidnotlocateexternalUCIimplementation.
- Baseline39964014518nativePASSbeforetestwrites. Tests-onlyacd6ce1:10newmethods; coreRED39965746616 extrarequestedHoppingargumentobservedbeforecoreproductiona66ba6a. CoreGREEN/AppRED39965966094running. NoAppproductionyet.
