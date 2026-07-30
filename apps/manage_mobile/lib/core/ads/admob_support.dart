import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_env.dart';

class ManageAdMobController {
  ManageAdMobController._();

  static final ManageAdMobController instance = ManageAdMobController._();

  static const String _androidTestBannerUnitId =
      "ca-app-pub-3940256099942544/9214589741";
  static const String _iosTestBannerUnitId =
      "ca-app-pub-3940256099942544/2435281174";

  bool _initialized = false;
  bool _mobileAdsInitialized = false;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  Future<void>? _initializationFuture;

  bool get canShowInlineBannerAds =>
      _canRequestAds && inlineBannerUnitId != null;
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  String? get inlineBannerUnitId {
    if (AppEnv.admobInlineBannerUnitId.isNotEmpty) {
      return AppEnv.admobInlineBannerUnitId;
    }
    if (!kDebugMode) {
      return null;
    }
    return Platform.isIOS ? _iosTestBannerUnitId : _androidTestBannerUnitId;
  }

  void warmUpIfNeeded() {
    _initializationFuture ??= initialize();
  }

  Future<void> initialize() async {
    final Future<void>? existing = _initializationFuture;
    if (existing != null) {
      return existing;
    }
    _initializationFuture = _initializeInternal();
    return _initializationFuture!;
  }

  Future<void> _initializeInternal() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (inlineBannerUnitId == null) {
      return;
    }

    final Completer<void> completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((
          FormError? error,
        ) async {
          _canRequestAds = await ConsentInformation.instance.canRequestAds();
          _privacyOptionsRequired = await _resolvePrivacyOptionsRequired();
          await _initializeMobileAdsIfAllowed();
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
      },
      (FormError error) async {
        _canRequestAds = await ConsentInformation.instance.canRequestAds();
        _privacyOptionsRequired = await _resolvePrivacyOptionsRequired();
        await _initializeMobileAdsIfAllowed();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );
    await completer.future;
  }

  Future<void> openPrivacyOptionsForm() async {
    if (!_privacyOptionsRequired) {
      return;
    }
    await ConsentForm.showPrivacyOptionsForm((FormError? _) {});
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    _privacyOptionsRequired = await _resolvePrivacyOptionsRequired();
    await _initializeMobileAdsIfAllowed();
  }

  Future<void> _initializeMobileAdsIfAllowed() async {
    if (_mobileAdsInitialized || !_canRequestAds) {
      return;
    }
    await MobileAds.instance.initialize();
    _mobileAdsInitialized = true;
  }

  Future<bool> _resolvePrivacyOptionsRequired() async {
    return await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }
}

class ManageAdPrivacyButton extends StatelessWidget {
  const ManageAdPrivacyButton({super.key});

  @override
  Widget build(BuildContext context) {
    ManageAdMobController.instance.warmUpIfNeeded();
    if (!ManageAdMobController.instance.privacyOptionsRequired) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          await ManageAdMobController.instance.openPrivacyOptionsForm();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Privacy options updated.")),
            );
          }
        },
        icon: const Icon(Icons.privacy_tip_outlined),
        label: const Text("Privacy choices"),
      ),
    );
  }
}

class ManageInlineBannerAdCard extends StatefulWidget {
  const ManageInlineBannerAdCard({super.key});

  @override
  State<ManageInlineBannerAdCard> createState() =>
      _ManageInlineBannerAdCardState();
}

class _ManageInlineBannerAdCardState extends State<ManageInlineBannerAdCard> {
  BannerAd? _bannerAd;
  double _adHeight = 0;
  int _lastWidth = 0;
  bool _loading = false;

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadForWidth(int width) async {
    if (_loading || width <= 0 || _lastWidth == width) {
      return;
    }
    if (!ManageAdMobController.instance.canShowInlineBannerAds) {
      return;
    }
    _loading = true;
    _lastWidth = width;
    await _bannerAd?.dispose();

    final AdSize adSize =
        AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(width);
    final BannerAd bannerAd = BannerAd(
      size: adSize,
      adUnitId: ManageAdMobController.instance.inlineBannerUnitId!,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) async {
          final AdSize? platformSize = await (ad as BannerAd)
              .getPlatformAdSize();
          if (!mounted) {
            return;
          }
          setState(() {
            _bannerAd = ad;
            _adHeight = (platformSize?.height ?? ad.size.height).toDouble();
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
          if (!mounted) {
            return;
          }
          setState(() {
            _bannerAd = null;
            _adHeight = 0;
          });
        },
      ),
    );

    await bannerAd.load();
    _loading = false;
  }

  @override
  Widget build(BuildContext context) {
    ManageAdMobController.instance.warmUpIfNeeded();
    if (!ManageAdMobController.instance.canShowInlineBannerAds) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int width = constraints.maxWidth.floor();
        if (width > 0 && width != _lastWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadForWidth(width);
          });
        }

        if (_bannerAd == null || _adHeight <= 0) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Advertisement",
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: width.toDouble(),
                  height: _adHeight,
                  child: AdWidget(ad: _bannerAd!),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
