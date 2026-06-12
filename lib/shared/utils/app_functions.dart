import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Functions region — MUST match `setGlobalOptions({ region })` in
/// functions/index.js (SCALE-08: co-located with the asia-south1 Firestore
/// database). `FirebaseFunctions.instance` silently defaults to us-central1,
/// where our functions no longer exist — every callable would 404 — so all
/// callable invocations must go through [appFunctions] instead.
const String kFunctionsRegion = 'asia-south1';

/// The app-wide [FirebaseFunctions] entry point, pinned to [kFunctionsRegion].
FirebaseFunctions get appFunctions =>
    FirebaseFunctions.instanceFor(region: kFunctionsRegion);
