import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// Start in Thai; easy_localization persists the user's explicit choice.
class AppLocalization extends StatelessWidget {
  const AppLocalization({
    super.key,
    required this.child,
    this.assetLoader = const RootBundleAssetLoader(),
  });
  final Widget child;
  final AssetLoader assetLoader;

  @override
  Widget build(BuildContext context) => EasyLocalization(
    supportedLocales: const [Locale('th'), Locale('en')],
    startLocale: const Locale('th'),
    fallbackLocale: const Locale('th'),
    path: 'assets/translations',
    assetLoader: assetLoader,
    child: child,
  );
}
