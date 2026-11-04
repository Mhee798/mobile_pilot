import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  await testMain();
}
