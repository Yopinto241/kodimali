import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_constants/shared_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'core/ads/admob_support.dart';
import 'core/cache/customer_snapshot_store.dart';
import 'core/data/customer_public_repository.dart';
import 'core/localization/customer_localization.dart';
import 'core/media/customer_media_cache.dart';

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key});

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  static const String _languagePrefKey = "customer_language_code";
  String _languageCode = "sw";
  bool _languageReady = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await CustomerSnapshotStore.initialize(prefs);
    setState(() {
      _languageCode = prefs.getString(_languagePrefKey) ?? "sw";
      _languageReady = true;
    });
  }

  Future<void> _setLanguageCode(String nextLanguageCode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefKey, nextLanguageCode);
    if (mounted) {
      setState(() => _languageCode = nextLanguageCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_languageReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return CustomerAppScope(
      languageCode: _languageCode,
      onLanguageChanged: _setLanguageCode,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: appName,
        theme: KodimaliTheme.light(),
        darkTheme: KodimaliTheme.dark(),
        themeMode: ThemeMode.system,
        locale: Locale(_languageCode),
        supportedLocales: const <Locale>[Locale("en"), Locale("sw")],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CustomerRoot(
          repository: CustomerPublicRepository(Supabase.instance.client),
        ),
      ),
    );
  }
}

class CustomerRoot extends StatefulWidget {
  const CustomerRoot({super.key, required this.repository});

  final CustomerPublicRepository repository;

  @override
  State<CustomerRoot> createState() => _CustomerRootState();
}

class _CustomerRootState extends State<CustomerRoot> {
  int _index = 0;
  int _refreshTick = 0;
  final Set<int> _visitedIndexes = <int>{0};
  String? _regionId;
  String? _districtId;
  String? _wardId;
  String? _areaId;
  double? _latitude;
  double? _longitude;
  bool _bannerHidden = false;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _loadPrefs();
  }

  late final _CustomerLifecycleObserver _lifecycleObserver =
      _CustomerLifecycleObserver(onResume: _handleAppResume);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? hiddenUntil = prefs.getInt(
      "customer_location_banner_hidden_until",
    );
    setState(() {
      _regionId = prefs.getString("customer_region_id");
      _districtId = prefs.getString("customer_district_id");
      _wardId = prefs.getString("customer_ward_id");
      _areaId = prefs.getString("customer_area_id");
      _latitude = prefs.getDouble("customer_latitude");
      _longitude = prefs.getDouble("customer_longitude");
      _bannerHidden =
          hiddenUntil != null &&
          DateTime.now().millisecondsSinceEpoch < hiddenUntil;
      _loadingPrefs = false;
    });
    _prewarmTabData();
  }

  Future<void> _savePreference({
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
    double? latitude,
    double? longitude,
    bool hideBanner = true,
    bool clearManualLocation = false,
    bool clearGps = false,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (clearManualLocation) {
      await prefs.remove("customer_region_id");
      await prefs.remove("customer_district_id");
      await prefs.remove("customer_ward_id");
      await prefs.remove("customer_area_id");
    }
    if (regionId != null) {
      await prefs.setString("customer_region_id", regionId);
    }
    if (districtId != null) {
      await prefs.setString("customer_district_id", districtId);
    }
    if (wardId != null) {
      await prefs.setString("customer_ward_id", wardId);
    }
    if (areaId != null) {
      await prefs.setString("customer_area_id", areaId);
    }
    if (clearGps) {
      await prefs.remove("customer_latitude");
      await prefs.remove("customer_longitude");
    }
    if (latitude != null && longitude != null) {
      await prefs.setDouble("customer_latitude", latitude);
      await prefs.setDouble("customer_longitude", longitude);
    }
    if (hideBanner) {
      await prefs.setInt(
        "customer_location_banner_hidden_until",
        DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _skipBanner() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      "customer_location_banner_hidden_until",
      DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
    );
    setState(() => _bannerHidden = true);
  }

  void _handleAppResume() {
    if (!mounted) {
      return;
    }
    widget.repository.invalidatePublicDataCache(includeCategories: true);
    setState(() => _refreshTick += 1);
  }

  Future<void> _useGps() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    );
    await _savePreference(
      latitude: position.latitude,
      longitude: position.longitude,
      clearManualLocation: true,
    );
    setState(() {
      _regionId = null;
      _districtId = null;
      _wardId = null;
      _areaId = null;
      _latitude = position.latitude;
      _longitude = position.longitude;
      _bannerHidden = true;
    });
    _prewarmTabData();
  }

  Future<void> _chooseLocation() async {
    final Map<String, String?>? result =
        await showModalBottomSheet<Map<String, String?>>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return LocationSelectorSheet(
              repository: widget.repository,
              initialRegionId: _regionId,
              initialDistrictId: _districtId,
              initialWardId: _wardId,
              initialAreaId: _areaId,
            );
          },
        );
    if (result == null) {
      return;
    }
    await _savePreference(
      regionId: result["regionId"],
      districtId: result["districtId"],
      wardId: result["wardId"],
      areaId: result["areaId"],
      clearManualLocation: true,
      clearGps: true,
    );
    setState(() {
      _regionId = result["regionId"];
      _districtId = result["districtId"];
      _wardId = result["wardId"];
      _areaId = result["areaId"];
      _latitude = null;
      _longitude = null;
      _bannerHidden = true;
    });
    _prewarmTabData();
  }

  void _prewarmTabData() {
    final CustomerPublicRepository repository = widget.repository;
    unawaited(repository.fetchCategories());
    unawaited(
      repository.fetchHomeFeed(
        limit: 10,
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
        sessionSeed: DateTime.now().day.toString(),
      ),
    );
    unawaited(
      repository.fetchPublicListings(
        categorySlug: "house",
        limit: 12,
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
        sessionSeed: "tab:house",
      ),
    );
    unawaited(
      repository.fetchPublicListings(
        categorySlug: "car",
        limit: 12,
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
        sessionSeed: "tab:car",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<Widget> pages = <Widget>[
      PublicHomeScreen(
        key: const PageStorageKey<String>("customer_home"),
        repository: widget.repository,
        refreshTick: _refreshTick,
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
        bannerHidden: _bannerHidden,
        onUseGps: _useGps,
        onChooseLocation: _chooseLocation,
        onSkipBanner: _skipBanner,
      ),
      PopularCategoryFeedScreen(
        key: const PageStorageKey<String>("customer_houses"),
        repository: widget.repository,
        refreshTick: _refreshTick,
        categorySlug: "house",
        title: context.tr("popular.houses.title"),
        subtitle: context.tr("popular.houses.subtitle"),
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
      ),
      PopularCategoryFeedScreen(
        key: const PageStorageKey<String>("customer_cars"),
        repository: widget.repository,
        refreshTick: _refreshTick,
        categorySlug: "car",
        title: context.tr("popular.cars.title"),
        subtitle: context.tr("popular.cars.subtitle"),
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
      ),
      PublicSearchScreen(
        key: const PageStorageKey<String>("customer_search"),
        repository: widget.repository,
        refreshTick: _refreshTick,
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
      ),
      CategoriesScreen(
        key: const PageStorageKey<String>("customer_categories"),
        repository: widget.repository,
        refreshTick: _refreshTick,
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        areaId: _areaId,
        latitude: _latitude,
        longitude: _longitude,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: List<Widget>.generate(pages.length, (int pageIndex) {
            if (_visitedIndexes.contains(pageIndex)) {
              return pages[pageIndex];
            }
            return const SizedBox.shrink();
          }),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int next) {
          setState(() {
            _index = next;
            _visitedIndexes.add(next);
          });
        },
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: context.tr("nav.home"),
          ),
          NavigationDestination(
            icon: const Icon(Icons.house_outlined),
            label: context.tr("nav.houses"),
          ),
          NavigationDestination(
            icon: const Icon(Icons.directions_car_outlined),
            label: context.tr("nav.cars"),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            label: context.tr("nav.search"),
          ),
          NavigationDestination(
            icon: const Icon(Icons.category_outlined),
            label: context.tr("nav.categories"),
          ),
        ],
      ),
    );
  }
}

class _ErrorMessageCard extends StatelessWidget {
  const _ErrorMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SelectableText(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PublicHomeScreen extends StatefulWidget {
  const PublicHomeScreen({
    super.key,
    required this.repository,
    required this.refreshTick,
    required this.regionId,
    required this.districtId,
    required this.wardId,
    required this.areaId,
    required this.latitude,
    required this.longitude,
    required this.bannerHidden,
    required this.onUseGps,
    required this.onChooseLocation,
    required this.onSkipBanner,
  });

  final CustomerPublicRepository repository;
  final int refreshTick;
  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? areaId;
  final double? latitude;
  final double? longitude;
  final bool bannerHidden;
  final Future<void> Function() onUseGps;
  final Future<void> Function() onChooseLocation;
  final Future<void> Function() onSkipBanner;

  @override
  State<PublicHomeScreen> createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends State<PublicHomeScreen> {
  _PublicHomeData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _data = _initialData();
    _loading = _data == null;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant PublicHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionId != widget.regionId ||
        oldWidget.districtId != widget.districtId ||
        oldWidget.wardId != widget.wardId ||
        oldWidget.areaId != widget.areaId ||
        oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.bannerHidden != widget.bannerHidden ||
        oldWidget.refreshTick != widget.refreshTick) {
      if (oldWidget.refreshTick != widget.refreshTick) {
        widget.repository.invalidatePublicDataCache(includeCategories: true);
      }
      _data = _initialData();
      _loading = _data == null;
      unawaited(_refresh());
    }
  }

  _PublicHomeData? _initialData() {
    final List<Map<String, dynamic>> categories =
        CustomerSnapshotStore.categories;
    final String homeKey = CustomerSnapshotStore.buildScopedKey(
      scope: "home",
      regionId: widget.regionId,
      districtId: widget.districtId,
      wardId: widget.wardId,
      areaId: widget.areaId,
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    final List<Map<String, dynamic>> homeFeed =
        CustomerSnapshotStore.homeFeedForKey(homeKey) ??
        <Map<String, dynamic>>[];
    if (categories.isEmpty && homeFeed.isEmpty) {
      return null;
    }
    return _PublicHomeData(
      categories: categories,
      feed: homeFeed,
      promotions: const <Map<String, dynamic>>[],
    );
  }

  Future<void> _refresh() async {
    final _PublicHomeData data = await _load();
    if (!mounted) {
      return;
    }
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<_PublicHomeData> _load() async {
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      widget.repository.fetchCategories(),
      widget.repository.fetchHomeFeed(
        limit: 10,
        regionId: widget.regionId,
        districtId: widget.districtId,
        wardId: widget.wardId,
        areaId: widget.areaId,
        latitude: widget.latitude,
        longitude: widget.longitude,
        sessionSeed: DateTime.now().day.toString(),
      ),
      widget.repository.fetchPromotions(
        surface: "customer_app",
        placement: "home_feed",
        limit: 6,
      ),
    ]);
    return _PublicHomeData(
      categories: (results[0] as List<dynamic>).cast<Map<String, dynamic>>(),
      feed: (results[1] as List<dynamic>).cast<Map<String, dynamic>>(),
      promotions: (results[2] as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  List<Map<String, dynamic>> _filterBySlugs(
    List<Map<String, dynamic>> feed,
    List<String> slugs,
  ) {
    return feed
        .where(
          (Map<String, dynamic> item) => slugs.contains(item["category_slug"]),
        )
        .toList();
  }

  Map<String, dynamic>? _findCategoryBySlug(
    List<Map<String, dynamic>> categories,
    String slug,
  ) {
    for (final Map<String, dynamic> category in categories) {
      if (category["slug"] == slug) {
        return category;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final _PublicHomeData data =
        _data ??
        const _PublicHomeData(
          categories: <Map<String, dynamic>>[],
          feed: <Map<String, dynamic>>[],
          promotions: <Map<String, dynamic>>[],
        );
    final List<Map<String, dynamic>> houses = _filterBySlugs(
      data.feed,
      <String>["house"],
    );
    final List<Map<String, dynamic>> carsAndBikes = _filterBySlugs(
      data.feed,
      <String>["car", "motorcycle"],
    );
    final List<Map<String, dynamic>> officesAndHalls = _filterBySlugs(
      data.feed,
      <String>["office", "meeting-hall", "ceremony-hall"],
    );
    final Map<String, dynamic>? houseCategory = _findCategoryBySlug(
      data.categories,
      "house",
    );
    final Map<String, dynamic>? carCategory = _findCategoryBySlug(
      data.categories,
      "car",
    );
    final List<Map<String, dynamic>> orderedCategories =
        List<Map<String, dynamic>>.from(data.categories)
          ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
            final int left = (a["display_order"] as num?)?.toInt() ?? 999;
            final int right = (b["display_order"] as num?)?.toInt() ?? 999;
            if (left != right) {
              return left.compareTo(right);
            }
            return (a["name"] as String? ?? "").compareTo(
              b["name"] as String? ?? "",
            );
          });
    final List<Map<String, dynamic>> otherListings = data.feed
        .where(
          (Map<String, dynamic> item) => !<String>[
            "house",
            "car",
            "motorcycle",
            "office",
            "meeting-hall",
            "ceremony-hall",
          ].contains(item["category_slug"]),
        )
        .toList();

    void openCategory(Map<String, dynamic> category) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CategoryListingsScreen(
            repository: widget.repository,
            category: category,
            regionId: widget.regionId,
            districtId: widget.districtId,
            wardId: widget.wardId,
            areaId: widget.areaId,
            latitude: widget.latitude,
            longitude: widget.longitude,
          ),
        ),
      );
    }

    void openSearch([String initialQuery = ""]) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(context.tr("nav.search"))),
            body: SafeArea(
              child: PublicSearchScreen(
                repository: widget.repository,
                regionId: widget.regionId,
                districtId: widget.districtId,
                wardId: widget.wardId,
                areaId: widget.areaId,
                latitude: widget.latitude,
                longitude: widget.longitude,
                refreshTick: widget.refreshTick,
                initialQuery: initialQuery,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KodimaliSpacing.md,
            KodimaliSpacing.md,
            KodimaliSpacing.md,
            KodimaliSpacing.xs,
          ),
          child: _HomeHeroCard(
            onOpenSearch: openSearch,
            onChooseLocation: widget.onChooseLocation,
            onUseGps: widget.onUseGps,
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              widget.repository.invalidatePublicDataCache(
                includeCategories: true,
              );
              await _refresh();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                KodimaliSpacing.md,
                0,
                KodimaliSpacing.md,
                KodimaliSpacing.xl,
              ),
              children: <Widget>[
                const CustomerAdPrivacyButton(),
                if (!widget.bannerHidden) ...<Widget>[
                  const SizedBox(height: KodimaliSpacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(KodimaliSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const KodimaliStatusBadge(
                            label: "Private location only",
                            tone: KodimaliStatusTone.info,
                          ),
                          const SizedBox(height: KodimaliSpacing.sm),
                          Text(
                            context.tr("banner.title"),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: KodimaliSpacing.xs),
                          Text(
                            "Tunatumia eneo la jumla tu ili kuonyesha listings zinazokufaa bila kufichua address kamili hadharani.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: KodimaliSpacing.sm),
                          Wrap(
                            spacing: KodimaliSpacing.xs,
                            runSpacing: KodimaliSpacing.xs,
                            children: <Widget>[
                              FilledButton(
                                onPressed: widget.onUseGps,
                                style: KodimaliButtonStyles.success(context),
                                child: Text(context.tr("hero.useLocation")),
                              ),
                              OutlinedButton(
                                onPressed: widget.onChooseLocation,
                                style: KodimaliButtonStyles.outline(context),
                                child: Text(context.tr("hero.chooseArea")),
                              ),
                              TextButton(
                                onPressed: widget.onSkipBanner,
                                child: Text(context.tr("banner.skip")),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: KodimaliSpacing.lg),
                _FeedSection(
                  title: context.tr("feed.nearYou"),
                  listings: data.feed,
                  promotions: data.promotions,
                  repository: widget.repository,
                  showAds: true,
                ),
                if (orderedCategories.isNotEmpty) ...<Widget>[
                  const SizedBox(height: KodimaliSpacing.lg),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          context.tr("heading.browseCategories"),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (houseCategory != null)
                        TextButton(
                          onPressed: () => openCategory(houseCategory),
                          child: Text(context.tr("hero.browseHouses")),
                        )
                      else if (carCategory != null)
                        TextButton(
                          onPressed: () => openCategory(carCategory),
                          child: Text(context.tr("hero.browseCars")),
                        ),
                    ],
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
                  SizedBox(
                    height: 124,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: orderedCategories.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: KodimaliSpacing.sm),
                      itemBuilder: (BuildContext context, int index) {
                        final Map<String, dynamic> category =
                            orderedCategories[index];
                        return _HomeCategoryCard(
                          category: category,
                          onTap: () => openCategory(category),
                        );
                      },
                    ),
                  ),
                ],
                const CustomerInlineBannerAdCard(),
                _FeedSection(
                  title: context.tr("feed.houses"),
                  listings: houses,
                  repository: widget.repository,
                ),
                _FeedSection(
                  title: context.tr("feed.cars"),
                  listings: carsAndBikes,
                  repository: widget.repository,
                ),
                _FeedSection(
                  title: context.tr("feed.offices"),
                  listings: officesAndHalls,
                  repository: widget.repository,
                ),
                _FeedSection(
                  title: context.tr("feed.other"),
                  listings: otherListings,
                  repository: widget.repository,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PublicSearchScreen extends StatefulWidget {
  const PublicSearchScreen({
    super.key,
    required this.repository,
    required this.regionId,
    required this.districtId,
    required this.wardId,
    required this.areaId,
    required this.latitude,
    required this.longitude,
    required this.refreshTick,
    this.initialQuery,
  });

  final CustomerPublicRepository repository;
  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? areaId;
  final double? latitude;
  final double? longitude;
  final int refreshTick;
  final String? initialQuery;

  @override
  State<PublicSearchScreen> createState() => _PublicSearchScreenState();
}

class _PublicSearchScreenState extends State<PublicSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _suggestions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _promotions = <Map<String, dynamic>>[];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;
  int _requestSequence = 0;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery ?? "";
    unawaited(_refreshSearch());
  }

  @override
  void didUpdateWidget(covariant PublicSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionId != widget.regionId ||
        oldWidget.districtId != widget.districtId ||
        oldWidget.wardId != widget.wardId ||
        oldWidget.areaId != widget.areaId ||
        oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.refreshTick != widget.refreshTick) {
      if (oldWidget.refreshTick != widget.refreshTick) {
        widget.repository.invalidatePublicDataCache();
      }
      unawaited(_refreshSearch(refreshPromotions: true));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _normalizedQuery => _searchController.text.trim();

  Future<List<Map<String, dynamic>>> _loadResults(String query) {
    return widget.repository.fetchPublicListings(
      limit: 20,
      searchText: query.isEmpty ? null : query,
      regionId: widget.regionId,
      districtId: widget.districtId,
      wardId: widget.wardId,
      areaId: widget.areaId,
      latitude: widget.latitude,
      longitude: widget.longitude,
      sessionSeed: query.isEmpty ? "search" : "search:$query",
    );
  }

  Future<List<Map<String, dynamic>>> _loadPromotions() {
    return widget.repository.fetchPromotions(
      surface: "customer_app",
      placement: "category_page",
      limit: 6,
    );
  }

  void _handleSearchChanged(String _) {
    setState(() => _errorMessage = null);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_refreshSearch()),
    );
  }

  Future<void> _refreshSearch({
    bool refreshPromotions = false,
    bool invalidateCache = false,
  }) async {
    final String query = _normalizedQuery.toLowerCase();
    final int requestId = ++_requestSequence;
    final bool hasVisibleContent =
        _results.isNotEmpty ||
        _promotions.isNotEmpty ||
        _suggestions.isNotEmpty;
    if (invalidateCache) {
      widget.repository.invalidatePublicDataCache();
    }
    if (mounted) {
      setState(() {
        _errorMessage = null;
        if (hasVisibleContent) {
          _isSearching = true;
        } else {
          _isLoading = true;
        }
      });
    }
    try {
      final Future<List<Map<String, dynamic>>> resultsFuture = _loadResults(
        query,
      );
      final Future<List<Map<String, dynamic>>> promotionsFuture =
          refreshPromotions || _promotions.isEmpty
          ? _loadPromotions()
          : Future<List<Map<String, dynamic>>>.value(_promotions);
      final List<dynamic> loaded = await Future.wait<dynamic>(<Future<dynamic>>[
        resultsFuture,
        promotionsFuture,
      ]);
      if (!mounted || requestId != _requestSequence) {
        return;
      }
      final List<Map<String, dynamic>> results = (loaded[0] as List)
          .cast<Map<String, dynamic>>();
      final List<Map<String, dynamic>> promotions = (loaded[1] as List)
          .cast<Map<String, dynamic>>();
      setState(() {
        _results = results;
        _suggestions = query.isEmpty
            ? <Map<String, dynamic>>[]
            : results.take(5).toList();
        _promotions = promotions;
        _isLoading = false;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestSequence) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
        _isSearching = false;
      });
    }
  }

  void _submitSearch() {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    unawaited(_refreshSearch());
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    unawaited(_refreshSearch());
  }

  void _openListing(String listingId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailScreen(
          repository: widget.repository,
          listingId: listingId,
        ),
      ),
    );
  }

  String _searchSummaryText(BuildContext context) {
    final String query = _normalizedQuery;
    if (_isLoading || _isSearching) {
      if (query.isEmpty) {
        return context.tr("search.searching");
      }
      return context.tr(
        "search.searchingQuery",
        values: <String, String>{"query": query},
      );
    }
    if (_results.isEmpty) {
      if (query.isEmpty) {
        return context.tr("search.empty");
      }
      return context.tr(
        "search.emptyQuery",
        values: <String, String>{"query": query},
      );
    }
    final Map<String, String> values = <String, String>{
      "count": _results.length.toString(),
      "query": query,
    };
    return query.isEmpty
        ? context.tr("search.resultCount", values: values)
        : context.tr("search.resultCountQuery", values: values);
  }

  String _searchSummarySubtitle(BuildContext context) {
    if (_errorMessage != null) {
      return _errorMessage!;
    }
    if (_isLoading || _isSearching) {
      return context.tr("search.liveHint");
    }
    if (_results.isEmpty) {
      return context.tr("search.tryAnother");
    }
    if (_normalizedQuery.isEmpty) {
      return context.tr("search.liveHint");
    }
    return context.tr("search.suggestionsHint");
  }

  @override
  Widget build(BuildContext context) {
    final String query = _normalizedQuery;
    final List<Widget> listChildren = <Widget>[
      _SearchSummaryCard(
        icon: _errorMessage != null
            ? Icons.error_outline
            : (_results.isEmpty
                  ? Icons.search_off_rounded
                  : Icons.search_rounded),
        title: _searchSummaryText(context),
        subtitle: _searchSummarySubtitle(context),
        showProgress: _isLoading || _isSearching,
        isError: _errorMessage != null,
      ),
    ];
    if (query.isNotEmpty && _suggestions.isNotEmpty) {
      listChildren.add(
        Padding(
          padding: const EdgeInsets.only(bottom: KodimaliSpacing.md),
          child: _SearchSuggestionsCard(
            title: context.tr("search.suggestions"),
            suggestions: _suggestions,
            onSelected: (Map<String, dynamic> suggestion) {
              final String? listingId = suggestion["listing_id"] as String?;
              if (listingId != null && listingId.isNotEmpty) {
                _openListing(listingId);
              }
            },
          ),
        ),
      );
    }
    if (_errorMessage != null) {
      listChildren.add(_ErrorMessageCard(message: _errorMessage!));
    } else if (!_isLoading && _results.isEmpty) {
      listChildren.add(
        Padding(
          padding: const EdgeInsets.only(top: KodimaliSpacing.lg),
          child: Center(
            child: KodimaliStatusBadge(
              label: context.tr("search.empty"),
              tone: KodimaliStatusTone.muted,
            ),
          ),
        ),
      );
    } else {
      listChildren.addAll(
        _buildListingChildren(
          listings: _results,
          promotions: query.isEmpty ? _promotions : <Map<String, dynamic>>[],
          repository: widget.repository,
          showAds: true,
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KodimaliSpacing.md,
            KodimaliSpacing.md,
            KodimaliSpacing.md,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: _handleSearchChanged,
                  onSubmitted: (_) => _submitSearch(),
                  decoration: InputDecoration(
                    labelText: context.tr("search.label"),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _clearSearch,
                            tooltip: context.tr("search.clear"),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    helperText: context.tr("search.liveHint"),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _submitSearch,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Icon(Icons.arrow_forward_rounded),
              ),
              const SizedBox(width: 12),
              const _LanguageSwitcherButton(),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _refreshSearch(
                refreshPromotions: true,
                invalidateCache: true,
              );
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: KodimaliSpacing.screenPadding,
              children: listChildren,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchSummaryCard extends StatelessWidget {
  const _SearchSummaryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showProgress = false,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool showProgress;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = isError
        ? theme.colorScheme.error
        : KodimaliColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: KodimaliSpacing.md),
      padding: const EdgeInsets.all(KodimaliSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KodimaliRadii.card),
        border: Border.all(
          color: isError
              ? theme.colorScheme.errorContainer
              : accent.withValues(alpha: 0.18),
        ),
        boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: accent),
              const SizedBox(width: KodimaliSpacing.sm),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: KodimaliSpacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (showProgress) ...<Widget>[
            const SizedBox(height: KodimaliSpacing.sm),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _SearchSuggestionsCard extends StatelessWidget {
  const _SearchSuggestionsCard({
    required this.title,
    required this.suggestions,
    required this.onSelected,
  });

  final String title;
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KodimaliRadii.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KodimaliSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KodimaliSpacing.sm,
                KodimaliSpacing.xs,
                KodimaliSpacing.sm,
                KodimaliSpacing.sm,
              ),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            ...suggestions.map((Map<String, dynamic> suggestion) {
              final String listingTitle = suggestion["title"] as String? ?? "-";
              final String category =
                  suggestion["category_name"] as String? ?? "Listing";
              final String location =
                  suggestion["public_location_label"] as String? ?? "-";
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: KodimaliSpacing.sm,
                ),
                leading: const Icon(Icons.search_rounded),
                title: Text(
                  listingTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  "$category • $location",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => onSelected(suggestion),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class PopularCategoryFeedScreen extends StatefulWidget {
  const PopularCategoryFeedScreen({
    super.key,
    required this.repository,
    required this.categorySlug,
    required this.title,
    required this.subtitle,
    required this.refreshTick,
    this.regionId,
    this.districtId,
    this.wardId,
    this.areaId,
    this.latitude,
    this.longitude,
  });

  final CustomerPublicRepository repository;
  final String categorySlug;
  final String title;
  final String subtitle;
  final int refreshTick;
  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? areaId;
  final double? latitude;
  final double? longitude;

  @override
  State<PopularCategoryFeedScreen> createState() =>
      _PopularCategoryFeedScreenState();
}

class _PopularCategoryFeedScreenState extends State<PopularCategoryFeedScreen> {
  List<Map<String, dynamic>> _listings = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _promotions = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _listings = _initialListings();
    _loading = _listings.isEmpty;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant PopularCategoryFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categorySlug != widget.categorySlug ||
        oldWidget.regionId != widget.regionId ||
        oldWidget.districtId != widget.districtId ||
        oldWidget.wardId != widget.wardId ||
        oldWidget.areaId != widget.areaId ||
        oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.refreshTick != widget.refreshTick) {
      if (oldWidget.refreshTick != widget.refreshTick) {
        widget.repository.invalidatePublicDataCache();
      }
      _listings = _initialListings();
      _loading = _listings.isEmpty;
      unawaited(_refresh());
    }
  }

  List<Map<String, dynamic>> _initialListings() {
    final String key = CustomerSnapshotStore.buildScopedKey(
      scope: widget.categorySlug,
      regionId: widget.regionId,
      districtId: widget.districtId,
      wardId: widget.wardId,
      areaId: widget.areaId,
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    return CustomerSnapshotStore.publicListingsForKey(key) ??
        <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> _load() {
    return widget.repository.fetchPublicListings(
      categorySlug: widget.categorySlug,
      limit: 30,
      regionId: widget.regionId,
      districtId: widget.districtId,
      wardId: widget.wardId,
      areaId: widget.areaId,
      latitude: widget.latitude,
      longitude: widget.longitude,
      sessionSeed: "tab:${widget.categorySlug}",
    );
  }

  Future<void> _refresh() async {
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      _load(),
      widget.repository.fetchPromotions(
        surface: "customer_app",
        placement: "category_page",
        limit: 6,
      ),
    ]);
    final List<Map<String, dynamic>> listings = (results[0] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> promotions = (results[1] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (!mounted) {
      return;
    }
    setState(() {
      _listings = listings;
      _promotions = promotions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _listings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<Map<String, dynamic>> listings = _listings;
    return RefreshIndicator(
      onRefresh: () async {
        widget.repository.invalidatePublicDataCache();
        await _refresh();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const KodimaliStatusBadge(
                    label: "Popular category",
                    tone: KodimaliStatusTone.info,
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const _LanguageSwitcherButton(),
                    ],
                  ),
                  const SizedBox(height: KodimaliSpacing.xs),
                  Text(widget.subtitle),
                ],
              ),
            ),
          ),
          if (listings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: KodimaliSpacing.lg),
              child: const Center(
                child: KodimaliStatusBadge(
                  label: "No listings in this category yet",
                  tone: KodimaliStatusTone.muted,
                ),
              ),
            )
          else ...<Widget>[
            const SizedBox(height: 12),
            ..._buildListingChildren(
              listings: listings,
              promotions: _promotions,
              repository: widget.repository,
            ),
          ],
        ],
      ),
    );
  }
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.repository,
    required this.refreshTick,
    this.regionId,
    this.districtId,
    this.wardId,
    this.areaId,
    this.latitude,
    this.longitude,
  });

  final CustomerPublicRepository repository;
  final int refreshTick;
  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? areaId;
  final double? latitude;
  final double? longitude;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _categories = CustomerSnapshotStore.categories;
    _loading = _categories.isEmpty;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant CategoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      widget.repository.invalidatePublicDataCache(includeCategories: true);
      _categories = CustomerSnapshotStore.categories;
      _loading = _categories.isEmpty;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final List<Map<String, dynamic>> categories = await widget.repository
        .fetchCategories();
    if (!mounted) {
      return;
    }
    setState(() {
      _categories = categories;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<Map<String, dynamic>> categories = _categories;
    return RefreshIndicator(
      onRefresh: () async {
        widget.repository.invalidatePublicDataCache(includeCategories: true);
        await _refresh();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr("heading.categories"),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const _LanguageSwitcherButton(),
            ],
          ),
          const SizedBox(height: KodimaliSpacing.md),
          ...List<Widget>.generate(categories.length, (int index) {
            final Map<String, dynamic> category = categories[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == categories.length - 1 ? 0 : 12,
              ),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(KodimaliSpacing.md),
                  title: Text(category["name"] as String? ?? "-"),
                  subtitle: Text(category["description"] as String? ?? "-"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryListingsScreen(
                          repository: widget.repository,
                          category: category,
                          regionId: widget.regionId,
                          districtId: widget.districtId,
                          wardId: widget.wardId,
                          areaId: widget.areaId,
                          latitude: widget.latitude,
                          longitude: widget.longitude,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CategoryListingsScreen extends StatelessWidget {
  const CategoryListingsScreen({
    super.key,
    required this.repository,
    required this.category,
    this.regionId,
    this.districtId,
    this.wardId,
    this.areaId,
    this.latitude,
    this.longitude,
  });

  final CustomerPublicRepository repository;
  final Map<String, dynamic> category;
  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? areaId;
  final double? latitude;
  final double? longitude;

  Future<_CategoryListingsData> _load() async {
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.fetchPublicListings(
        categorySlug: category["slug"] as String?,
        limit: 30,
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: areaId,
        latitude: latitude,
        longitude: longitude,
        sessionSeed: category["slug"] as String?,
      ),
      repository.fetchHomeFeed(
        limit: 10,
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: areaId,
        latitude: latitude,
        longitude: longitude,
        sessionSeed: "fallback:${category["slug"] as String? ?? "category"}",
      ),
      repository.fetchPromotions(
        surface: "customer_app",
        placement: "category_page",
        limit: 6,
      ),
    ]);
    return _CategoryListingsData(
      listings: (results[0] as List<dynamic>).cast<Map<String, dynamic>>(),
      fallbackListings: (results[1] as List<dynamic>)
          .cast<Map<String, dynamic>>(),
      promotions: (results[2] as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          category["name"] as String? ?? context.tr("category.titleFallback"),
        ),
        actions: const <Widget>[_LanguageSwitcherButton()],
      ),
      body: FutureBuilder<_CategoryListingsData>(
        future: _load(),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<_CategoryListingsData> snapshot,
            ) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _CategoryPageShell(
                  category: category,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.tr("category.error"),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }
              final _CategoryListingsData data =
                  snapshot.data ??
                  const _CategoryListingsData(
                    listings: <Map<String, dynamic>>[],
                    fallbackListings: <Map<String, dynamic>>[],
                    promotions: <Map<String, dynamic>>[],
                  );
              final List<Map<String, dynamic>> listings = data.listings;
              final List<Map<String, dynamic>> promotions = data.promotions;
              final List<Map<String, dynamic>> fallbackListings = data
                  .fallbackListings
                  .where(
                    (Map<String, dynamic> item) =>
                        item["category_slug"] != category["slug"],
                  )
                  .toList();

              return _CategoryPageShell(
                category: category,
                child: ListView(
                  padding: KodimaliSpacing.screenPadding,
                  children: <Widget>[
                    if (listings.isNotEmpty)
                      ..._buildListingChildren(
                        listings: listings,
                        promotions: promotions,
                        repository: repository,
                      )
                    else ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(KodimaliSpacing.md),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            KodimaliRadii.card,
                          ),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.tr("category.empty"),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(context.tr("category.tryOthers")),
                          ],
                        ),
                      ),
                      if (fallbackListings.isNotEmpty) ...<Widget>[
                        const SizedBox(height: KodimaliSpacing.lg),
                        Text(
                          context.tr("category.related"),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        ...fallbackListings.map(
                          (Map<String, dynamic> listing) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PublicListingCard(
                              listing: listing,
                              repository: repository,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
      ),
    );
  }
}

class _CategoryPageShell extends StatelessWidget {
  const _CategoryPageShell({required this.category, required this.child});

  final Map<String, dynamic> category;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          margin: const EdgeInsets.fromLTRB(
            KodimaliSpacing.md,
            KodimaliSpacing.md,
            KodimaliSpacing.md,
            0,
          ),
          width: double.infinity,
          padding: const EdgeInsets.all(KodimaliSpacing.lg),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[KodimaliColors.navy, KodimaliColors.blueSurface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(KodimaliRadii.hero),
            boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const KodimaliStatusBadge(
                label: "Category focus",
                tone: KodimaliStatusTone.active,
              ),
              const SizedBox(height: KodimaliSpacing.sm),
              Text(
                context.tr("category.browseTitle"),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: KodimaliSpacing.sm),
              Text(
                category["name"] as String? ??
                    context.tr("category.titleFallback"),
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: KodimaliSpacing.xs),
              Text(
                (category["description"] as String?)?.trim().isNotEmpty == true
                    ? category["description"] as String
                    : context.tr("category.browseBody"),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _CategoryListingsData {
  const _CategoryListingsData({
    required this.listings,
    required this.fallbackListings,
    required this.promotions,
  });

  final List<Map<String, dynamic>> listings;
  final List<Map<String, dynamic>> fallbackListings;
  final List<Map<String, dynamic>> promotions;
}

class PublicListingCard extends StatelessWidget {
  const PublicListingCard({
    super.key,
    required this.listing,
    required this.repository,
  });

  final Map<String, dynamic> listing;
  final CustomerPublicRepository repository;

  @override
  Widget build(BuildContext context) {
    final String? coverUrl = listing["cover_url"] as String?;
    final String? coverStoragePath = listing["cover_storage_path"] as String?;
    final ThemeData theme = Theme.of(context);
    final String categoryName =
        listing["category_name"] as String? ?? "Listing";
    final String agentName =
        listing["agent_display_name"] as String? ?? "Agent";
    final String? agentPhotoUrl = listing["agent_profile_photo_url"] as String?;
    final bool verified =
        (listing["agent_verification_status"] as String?) == "approved";
    final String locationLabel =
        listing["public_location_label"] as String? ?? "-";
    final String title = listing["title"] as String? ?? "-";
    final String priceLabel =
        "TZS ${listing["price_amount"] ?? "-"} / ${listing["price_period"] ?? "-"}";
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KodimaliRadii.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KodimaliSpacing.md,
              KodimaliSpacing.md,
              KodimaliSpacing.md,
              KodimaliSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                _CustomerAgentAvatar(
                  imageUrl: agentPhotoUrl,
                  fallbackText: agentName,
                  verified: false,
                ),
                const SizedBox(width: KodimaliSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        agentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (verified)
                  const KodimaliStatusBadge(
                    label: "Verified",
                    tone: KodimaliStatusTone.active,
                  )
                else
                  KodimaliStatusBadge(
                    label: context.tr("listing.public"),
                    tone: KodimaliStatusTone.info,
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(KodimaliRadii.card),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ListingDetailScreen(
                        repository: repository,
                        listingId: listing["listing_id"] as String,
                      ),
                    ),
                  );
                },
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      coverUrl == null
                          ? Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_outlined,
                                size: 52,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            )
                          : _NetworkMediaImage(
                              imageUrl: coverUrl,
                              cacheKey: coverStoragePath ?? coverUrl,
                              fit: BoxFit.contain,
                            ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.black.withValues(alpha: 0.05),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.12),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: KodimaliSpacing.sm,
                        left: KodimaliSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: KodimaliColors.navy.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            priceLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KodimaliSpacing.md,
              KodimaliSpacing.sm,
              KodimaliSpacing.md,
              KodimaliSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: KodimaliSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.place_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locationLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: KodimaliSpacing.sm),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ListingDetailScreen(
                              repository: repository,
                              listingId: listing["listing_id"] as String,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(context.tr("listing.view")),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListingDetailScreen extends StatelessWidget {
  const ListingDetailScreen({
    super.key,
    required this.repository,
    required this.listingId,
  });

  final CustomerPublicRepository repository;
  final String listingId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr("listing.details")),
        actions: const <Widget>[_LanguageSwitcherButton()],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: repository.fetchListingDetail(listingId),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<Map<String, dynamic>> snapshot,
            ) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorMessageCard(message: snapshot.error.toString());
              }
              final Map<String, dynamic> listing =
                  snapshot.data ?? <String, dynamic>{};
              final Map<String, dynamic>? category =
                  listing["asset_categories"] as Map<String, dynamic>?;
              final List<Map<String, dynamic>> fieldSchema =
                  (category?["field_schema"] as List<dynamic>? ?? <dynamic>[])
                      .map(
                        (dynamic item) => (item as Map).cast<String, dynamic>(),
                      )
                      .toList();
              final Map<String, dynamic> attributes =
                  listing["listing_attributes"] as Map<String, dynamic>? ??
                  <String, dynamic>{};
              final Map<String, dynamic> agentSummary =
                  listing["agent_summary"] as Map<String, dynamic>? ??
                  <String, dynamic>{};
              final List<dynamic> media =
                  listing["listing_media"] as List<dynamic>? ?? <dynamic>[];
              final List<_ListingAttributeItem> detailItems =
                  _buildListingAttributeItems(
                    context: context,
                    attributes: attributes,
                    fieldSchema: fieldSchema,
                  );

              return ListView(
                padding: KodimaliSpacing.screenPadding,
                children: <Widget>[
                  _ListingMediaGallery(media: media),
                  if (media.isNotEmpty)
                    const SizedBox(height: KodimaliSpacing.md),
                  KodimaliStatusBadge(
                    label: category?["name"] as String? ?? "-",
                    tone: KodimaliStatusTone.info,
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
                  Text(
                    listing["title"] as String? ?? "-",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: KodimaliSpacing.xs),
                  Text(
                    listing["public_location_label"] as String? ?? "-",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(KodimaliSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            "TZS ${listing["price_amount"] ?? "-"} / ${listing["price_period"] ?? "-"}",
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: KodimaliSpacing.xs),
                          Text(
                            listing["description"] as String? ?? "-",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: KodimaliButtonStyles.success(context),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GuestRequestScreen(
                              repository: repository,
                              listingId: listingId,
                            ),
                          ),
                        );
                      },
                      child: Text(context.tr("listing.request")),
                    ),
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  _AgentSummaryCard(agentSummary: agentSummary),
                  if ((category?["slug"] as String?) == "farms") ...<Widget>[
                    const SizedBox(height: KodimaliSpacing.md),
                    _FarmHighlights(
                      categorySlug: category?["slug"] as String?,
                      attributes: attributes,
                    ),
                  ],
                  if (detailItems.isNotEmpty) ...<Widget>[
                    const SizedBox(height: KodimaliSpacing.md),
                    Text(
                      context.tr("listing.additionalDetails"),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: KodimaliSpacing.sm),
                    ...detailItems.map(
                      (_ListingAttributeItem item) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: KodimaliSpacing.xs,
                        ),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(KodimaliSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                const SizedBox(width: KodimaliSpacing.sm),
                                Expanded(
                                  child: Text(
                                    item.value,
                                    textAlign: TextAlign.right,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: repository.fetchPromotions(
                      surface: "customer_app",
                      placement: "listing_detail",
                      limit: 1,
                    ),
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<List<Map<String, dynamic>>>
                          promotionSnapshot,
                        ) {
                          final List<Map<String, dynamic>> promotions =
                              promotionSnapshot.data ??
                              <Map<String, dynamic>>[];
                          if (promotions.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: KodimaliSpacing.md,
                            ),
                            child: _PromotionBlock(promotions: promotions),
                          );
                        },
                  ),
                ],
              );
            },
      ),
    );
  }
}

class _ListingMediaGallery extends StatefulWidget {
  const _ListingMediaGallery({required this.media});

  final List<dynamic> media;

  @override
  State<_ListingMediaGallery> createState() => _ListingMediaGalleryState();
}

class _ListingMediaGalleryState extends State<_ListingMediaGallery> {
  late final PageController _controller;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Map<String, dynamic>> visibleMedia = widget.media
        .map((dynamic item) => (item as Map).cast<String, dynamic>())
        .where(
          (Map<String, dynamic> item) =>
              (item["signed_url"] as String?)?.isNotEmpty == true,
        )
        .toList();
    if (visibleMedia.isEmpty) {
      return const SizedBox.shrink();
    }
    final double galleryHeight = MediaQuery.sizeOf(
      context,
    ).width.clamp(320.0, 420.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              context.tr("listing.media"),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            Text(
              "${_currentIndex + 1}/${visibleMedia.length}",
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: galleryHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: visibleMedia.length,
            onPageChanged: (int index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> mediaItem = visibleMedia[index];
              final String signedUrl = mediaItem["signed_url"] as String;
              final String cacheKey =
                  mediaItem["storage_path"] as String? ??
                  mediaItem["signed_url"] as String? ??
                  "listing-media-$index";
              return ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: mediaItem["media_type"] == "video"
                    ? _AutoPlayListingVideo(
                        videoUrl: signedUrl,
                        cacheKey: cacheKey,
                      )
                    : Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _FullscreenImageScreen(
                                  imageUrl: signedUrl,
                                  cacheKey: cacheKey,
                                ),
                              ),
                            );
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              Center(
                                child: _NetworkMediaImage(
                                  imageUrl: signedUrl,
                                  cacheKey: cacheKey,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.38),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
        if (visibleMedia.length > 1) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(visibleMedia.length, (int index) {
              final bool selected = index == _currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: selected ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _AutoPlayListingVideo extends StatefulWidget {
  const _AutoPlayListingVideo({required this.videoUrl, required this.cacheKey});

  final String videoUrl;
  final String cacheKey;

  @override
  State<_AutoPlayListingVideo> createState() => _AutoPlayListingVideoState();
}

class _AutoPlayListingVideoState extends State<_AutoPlayListingVideo> {
  VideoPlayerController? _controller;
  late final Future<void> _initialization;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    final File mediaFile = await CustomerMediaCacheManager.instance
        .getSingleFile(widget.videoUrl, key: widget.cacheKey);
    final VideoPlayerController controller = VideoPlayerController.file(
      mediaFile,
    );
    _controller = controller;
    await controller.initialize();
    await controller.setLooping(false);
    await controller.setVolume(0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleMuted() async {
    _muted = !_muted;
    await _controller?.setVolume(_muted ? 0 : 1);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        final VideoPlayerController? controller = _controller;
        if (snapshot.connectionState != ConnectionState.done) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Center(child: Text(context.tr("media.loading"))),
          );
        }
        if (snapshot.hasError || controller == null) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Center(child: Icon(Icons.videocam_off_outlined)),
          );
        }

        return GestureDetector(
          onTap: _togglePlayPause,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.12),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.tr("media.tapToPlay"),
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Row(
                  children: <Widget>[
                    _MediaActionButton(
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onTap: _toggleMuted,
                    ),
                    const SizedBox(width: 8),
                    _MediaActionButton(
                      icon: controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: _togglePlayPause,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaActionButton extends StatelessWidget {
  const _MediaActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _NetworkMediaImage extends StatelessWidget {
  const _NetworkMediaImage({
    required this.imageUrl,
    required this.cacheKey,
    this.fit = BoxFit.cover,
  });

  final String? imageUrl;
  final String cacheKey;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      cacheManager: CustomerMediaCacheManager.instance,
      cacheKey: cacheKey,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (BuildContext context, String _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (BuildContext context, String _, Object error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class GuestRequestScreen extends StatefulWidget {
  const GuestRequestScreen({
    super.key,
    required this.repository,
    required this.listingId,
  });

  final CustomerPublicRepository repository;
  final String listingId;

  @override
  State<GuestRequestScreen> createState() => _GuestRequestScreenState();
}

class _GuestRequestScreenState extends State<GuestRequestScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final String reference = await widget.repository.submitGuestRequest(
        listingId: widget.listingId,
        customerName: _nameController.text.trim(),
        customerPhoneNumber: _phoneController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RequestSuccessScreen(reference: reference),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr("request.form")),
        actions: const <Widget>[_LanguageSwitcherButton()],
      ),
      body: ListView(
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const KodimaliStatusBadge(
                    label: "Secure request",
                    tone: KodimaliStatusTone.active,
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
                  Text(
                    "Tuma jina na namba ya simu tu. Wakala anayehusika atakufuata kwa simu au WhatsApp kuthibitisha upatikanaji.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KodimaliSpacing.md),
          Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: context.tr("request.fullName"),
                    helperText: "Mfano: Amina Said",
                  ),
                  validator: (String? value) =>
                      value == null || value.trim().length < 2
                      ? context.tr("request.nameError")
                      : null,
                ),
                const SizedBox(height: KodimaliSpacing.md),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.tr("request.phone"),
                    helperText: "Tutaitumia kwa simu au WhatsApp tu.",
                  ),
                  validator: (String? value) =>
                      value == null || value.trim().length < 8
                      ? context.tr("request.phoneError")
                      : null,
                ),
                const SizedBox(height: KodimaliSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: KodimaliButtonStyles.success(context),
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _submitting
                          ? context.tr("request.submitting")
                          : context.tr("request.submit"),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: widget.repository.fetchPromotions(
                    surface: "customer_app",
                    placement: "listing_detail",
                    limit: 1,
                  ),
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
                      ) {
                        final List<Map<String, dynamic>> promotions =
                            snapshot.data ?? <Map<String, dynamic>>[];
                        if (promotions.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(
                            top: KodimaliSpacing.md,
                          ),
                          child: _PromotionBlock(promotions: promotions),
                        );
                      },
                ),
                const SizedBox(height: KodimaliSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(KodimaliSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          "Kinachofuata",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: KodimaliSpacing.xs),
                        Text(
                          "Baada ya kutuma ombi, wakala atakuthibitishia bei, upatikanaji, na hatua ya kuona mali hiyo.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RequestSuccessScreen extends StatelessWidget {
  const RequestSuccessScreen({super.key, required this.reference});

  final String reference;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(KodimaliSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const KodimaliStatusBadge(
                      label: "Request sent",
                      tone: KodimaliStatusTone.active,
                    ),
                    const SizedBox(height: KodimaliSpacing.sm),
                    Text(
                      context.tr("request.successTitle"),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: KodimaliSpacing.sm),
                    Text(
                      context.tr("request.successBody"),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: KodimaliSpacing.sm),
                    Text(
                      context.tr(
                        "request.reference",
                        values: <String, String>{"reference": reference},
                      ),
                    ),
                    const SizedBox(height: KodimaliSpacing.lg),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: CustomerPublicRepository(Supabase.instance.client)
                          .fetchPromotions(
                            surface: "customer_app",
                            placement: "listing_detail",
                            limit: 1,
                          ),
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
                          ) {
                            final List<Map<String, dynamic>> promotions =
                                snapshot.data ?? <Map<String, dynamic>>[];
                            if (promotions.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _PromotionBlock(promotions: promotions);
                          },
                    ),
                    const SizedBox(height: KodimaliSpacing.lg),
                    FilledButton(
                      style: KodimaliButtonStyles.success(context),
                      onPressed: () => Navigator.of(
                        context,
                      ).popUntil((Route<dynamic> route) => route.isFirst),
                      child: Text(context.tr("request.backHome")),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LocationSelectorSheet extends StatefulWidget {
  const LocationSelectorSheet({
    super.key,
    required this.repository,
    this.initialRegionId,
    this.initialDistrictId,
    this.initialWardId,
    this.initialAreaId,
  });

  final CustomerPublicRepository repository;
  final String? initialRegionId;
  final String? initialDistrictId;
  final String? initialWardId;
  final String? initialAreaId;

  @override
  State<LocationSelectorSheet> createState() => _LocationSelectorSheetState();
}

class _LocationSelectorSheetState extends State<LocationSelectorSheet> {
  List<Map<String, dynamic>> _regions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _districts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _wards = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _areas = <Map<String, dynamic>>[];
  String? _regionId;
  String? _districtId;
  String? _wardId;
  String? _areaId;
  bool _loading = true;
  bool _loadingChildren = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _errorMessage = null;
      final List<Map<String, dynamic>> countries = await widget.repository
          .fetchLocations(parentId: null, locationType: "country");
      List<Map<String, dynamic>> regions = <Map<String, dynamic>>[];
      final String? countryId = countries.isNotEmpty
          ? countries.first["id"] as String
          : null;
      if (countryId != null) {
        regions = await widget.repository.fetchLocations(
          parentId: countryId,
          locationType: "region",
        );
      }
      if (regions.isEmpty) {
        regions = await widget.repository.fetchLocations(
          parentId: null,
          locationType: "region",
        );
      }
      if (!mounted) {
        return;
      }
      _regions = regions;
      _regionId = _pickExistingId(_regions, widget.initialRegionId);
      if (_regionId != null) {
        await _loadDistricts(
          _regionId!,
          initialDistrictId: widget.initialDistrictId,
          initialWardId: widget.initialWardId,
          initialAreaId: widget.initialAreaId,
        );
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  String? _pickExistingId(
    List<Map<String, dynamic>> items,
    String? requestedId,
  ) {
    if (requestedId == null) {
      return null;
    }
    for (final Map<String, dynamic> item in items) {
      if (item["id"] == requestedId) {
        return requestedId;
      }
    }
    return null;
  }

  Future<void> _loadDistricts(
    String regionId, {
    String? initialDistrictId,
    String? initialWardId,
    String? initialAreaId,
  }) async {
    setState(() {
      _loadingChildren = true;
      _districts = <Map<String, dynamic>>[];
      _wards = <Map<String, dynamic>>[];
      _areas = <Map<String, dynamic>>[];
      _districtId = null;
      _wardId = null;
      _areaId = null;
    });
    final List<Map<String, dynamic>> districts = await widget.repository
        .fetchLocations(parentId: regionId, locationType: "district");
    if (!mounted) {
      return;
    }
    setState(() {
      _districts = districts;
      _districtId = _pickExistingId(districts, initialDistrictId);
      _loadingChildren = false;
    });
    if (_districtId != null) {
      await _loadWards(
        _districtId!,
        initialWardId: initialWardId,
        initialAreaId: initialAreaId,
      );
    }
  }

  Future<void> _loadWards(
    String districtId, {
    String? initialWardId,
    String? initialAreaId,
  }) async {
    if (mounted) {
      setState(() {
        _loadingChildren = true;
        _wards = <Map<String, dynamic>>[];
        _areas = <Map<String, dynamic>>[];
        _wardId = null;
        _areaId = null;
      });
    }

    final List<Map<String, dynamic>> wards = await widget.repository
        .fetchLocations(parentId: districtId, locationType: "ward");
    final String? nextWardId = _pickExistingId(wards, initialWardId);
    List<Map<String, dynamic>> areas = <Map<String, dynamic>>[];
    if (nextWardId != null) {
      areas = await widget.repository.fetchLocations(
        parentId: nextWardId,
        locationType: "area",
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _wards = wards;
      _areas = areas;
      _wardId = nextWardId;
      _areaId = _pickExistingId(areas, initialAreaId);
      _loadingChildren = false;
    });
  }

  Future<void> _loadAreasForWard(String? wardId) async {
    setState(() {
      _loadingChildren = true;
      _wardId = wardId;
      _areas = <Map<String, dynamic>>[];
      _areaId = null;
    });
    if (wardId == null) {
      setState(() {
        _loadingChildren = false;
      });
      return;
    }
    final List<Map<String, dynamic>> areas = await widget.repository
        .fetchLocations(parentId: wardId, locationType: "area");
    if (!mounted) {
      return;
    }
    setState(() {
      _areas = areas;
      _loadingChildren = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.tr("location.failed")),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _bootstrap();
                },
                child: Text(context.tr("location.retry")),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _regionId,
            decoration: InputDecoration(
              labelText: context.tr("location.region"),
            ),
            items: _regions
                .map(
                  (Map<String, dynamic> region) => DropdownMenuItem<String>(
                    value: region["id"] as String,
                    child: Text(region["name"] as String? ?? "-"),
                  ),
                )
                .toList(),
            onChanged: (String? value) async {
              setState(() {
                _regionId = value;
                _districts = <Map<String, dynamic>>[];
                _wards = <Map<String, dynamic>>[];
                _areas = <Map<String, dynamic>>[];
                _districtId = null;
                _wardId = null;
                _areaId = null;
              });
              if (value != null) {
                await _loadDistricts(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _districtId,
            decoration: InputDecoration(
              labelText: context.tr("location.district"),
              helperText: context.tr("location.chooseOptional"),
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: "",
                child: Text(context.tr("location.clearDistrict")),
              ),
              ..._districts.map(
                (Map<String, dynamic> district) => DropdownMenuItem<String>(
                  value: district["id"] as String,
                  child: Text(district["name"] as String? ?? "-"),
                ),
              ),
            ],
            onChanged: (String? value) async {
              final String? nextDistrictId = value == null || value.isEmpty
                  ? null
                  : value;
              setState(() {
                _districtId = nextDistrictId;
                _wards = <Map<String, dynamic>>[];
                _areas = <Map<String, dynamic>>[];
                _wardId = null;
                _areaId = null;
              });
              if (nextDistrictId != null) {
                await _loadWards(nextDistrictId);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _wardId ?? "",
            decoration: InputDecoration(
              labelText: context.tr("location.ward"),
              helperText: context.tr("location.chooseOptional"),
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: "",
                child: Text(context.tr("location.clearWard")),
              ),
              ..._wards.map(
                (Map<String, dynamic> ward) => DropdownMenuItem<String>(
                  value: ward["id"] as String,
                  child: Text(ward["name"] as String? ?? "-"),
                ),
              ),
            ],
            onChanged: _districtId == null || _loadingChildren
                ? null
                : (String? value) {
                    final String? nextWardId = value == null || value.isEmpty
                        ? null
                        : value;
                    _loadAreasForWard(nextWardId);
                  },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _areaId ?? "",
            decoration: InputDecoration(
              labelText: context.tr("location.area"),
              helperText: context.tr("location.chooseOptional"),
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: "",
                child: Text(context.tr("location.clearArea")),
              ),
              ..._areas.map(
                (Map<String, dynamic> area) => DropdownMenuItem<String>(
                  value: area["id"] as String,
                  child: Text(area["name"] as String? ?? "-"),
                ),
              ),
            ],
            onChanged: _loadingChildren
                ? null
                : (String? value) {
                    setState(() {
                      _areaId = value == null || value.isEmpty ? null : value;
                    });
                  },
          ),
          if (_loadingChildren) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _regionId == null
                  ? null
                  : () => Navigator.of(context).pop(<String, String?>{
                      "regionId": _regionId,
                      "districtId": _districtId,
                      "wardId": _wardId,
                      "areaId": _areaId,
                    }),
              child: Text(context.tr("location.useThis")),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedSection extends StatelessWidget {
  const _FeedSection({
    required this.title,
    required this.listings,
    this.promotions = const <Map<String, dynamic>>[],
    required this.repository,
    this.showAds = false,
  });

  final String title;
  final List<Map<String, dynamic>> listings;
  final List<Map<String, dynamic>> promotions;
  final CustomerPublicRepository repository;
  final bool showAds;

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 24),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ..._buildListingChildren(
          listings: listings,
          promotions: promotions,
          repository: repository,
          showAds: showAds,
        ),
      ],
    );
  }
}

List<Widget> _buildListingChildren({
  required List<Map<String, dynamic>> listings,
  required CustomerPublicRepository repository,
  List<Map<String, dynamic>> promotions = const <Map<String, dynamic>>[],
  bool showAds = false,
}) {
  final List<Widget> children = <Widget>[];
  int promotionIndex = 0;
  for (int index = 0; index < listings.length; index += 1) {
    children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PublicListingCard(
          listing: listings[index],
          repository: repository,
        ),
      ),
    );
    final bool hasMoreListings = index < listings.length - 1;
    if (promotions.isNotEmpty && (index + 1) % 3 == 0 && hasMoreListings) {
      final Map<String, dynamic> promotion =
          promotions[promotionIndex % promotions.length];
      promotionIndex += 1;
      children.add(
        _PromotionBlock(promotions: <Map<String, dynamic>>[promotion]),
      );
    }
    if (showAds && (index + 1) % 8 == 0 && hasMoreListings) {
      children.add(const CustomerNativeFeedAdCard());
    }
  }
  return children;
}

class _HomeCategoryCard extends StatelessWidget {
  const _HomeCategoryCard({required this.category, required this.onTap});

  final Map<String, dynamic> category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = category["name"] as String? ?? "-";
    final String description = category["description"] as String? ?? "";
    final String slug = category["slug"] as String? ?? "";

    return SizedBox(
      width: 158,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KodimaliRadii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(KodimaliRadii.card),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KodimaliRadii.card),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
            ),
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(
                      _categoryIconForSlug(slug),
                      size: 16,
                      color: KodimaliColors.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (description.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeroCard extends StatefulWidget {
  const _HomeHeroCard({
    required this.onOpenSearch,
    required this.onChooseLocation,
    required this.onUseGps,
  });

  final void Function([String initialQuery]) onOpenSearch;
  final Future<void> Function() onChooseLocation;
  final Future<void> Function() onUseGps;

  @override
  State<_HomeHeroCard> createState() => _HomeHeroCardState();
}

class _HomeHeroCardState extends State<_HomeHeroCard> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _hintTimer;
  bool _searchExpanded = false;
  bool _showActionHints = true;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showActionHints = false);
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchExpanded = !_searchExpanded);
    if (_searchExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    } else {
      _searchFocusNode.unfocus();
    }
  }

  void _submitSearch() {
    widget.onOpenSearch(_searchController.text.trim());
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    const Color heroBrownDark = Color(0xFF6B4328);
    const Color heroBrownLight = Color(0xFF8A5A35);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KodimaliSpacing.sm),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[heroBrownDark, heroBrownLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.all(
          Radius.circular(KodimaliRadii.card),
        ),
        boxShadow: KodimaliShadows.soft(heroBrownDark),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                "KODIMALI",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: KodimaliSpacing.sm),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KodimaliRadii.input),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: _searchExpanded
                            ? _submitSearch
                            : _toggleSearch,
                        icon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      if (_searchExpanded)
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onSubmitted: (_) => _submitSearch(),
                            style: const TextStyle(color: Colors.white),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: context.tr("search.label"),
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: GestureDetector(
                            onTap: _toggleSearch,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Search",
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.78,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      if (_searchExpanded)
                        IconButton(
                          onPressed: _toggleSearch,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: KodimaliSpacing.xs),
              const _LanguageSwitcherButton(compact: false),
            ],
          ),
          const SizedBox(height: KodimaliSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compactActions = constraints.maxWidth < 320;
              final bool showInlineLabels = _showActionHints && !compactActions;
              return Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: KodimaliSpacing.xs,
                  runSpacing: KodimaliSpacing.xs,
                  children: <Widget>[
                    _HeaderActionIcon(
                      icon: Icons.my_location_rounded,
                      label: context.tr("hero.useLocation"),
                      showLabel: showInlineLabels,
                      onTap: widget.onUseGps,
                    ),
                    _HeaderActionIcon(
                      icon: Icons.place_outlined,
                      label: context.tr("hero.chooseArea"),
                      showLabel: showInlineLabels,
                      onTap: widget.onChooseLocation,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderActionIcon extends StatelessWidget {
  const _HeaderActionIcon({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool showLabel;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? KodimaliSpacing.sm : 0,
          vertical: 0,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(KodimaliRadii.pill),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              onPressed: onTap,
              icon: Icon(icon, color: Colors.white, size: 18),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: showLabel
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(right: KodimaliSpacing.sm),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSwitcherButton extends StatelessWidget {
  const _LanguageSwitcherButton({this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool swahili = context.isSwahili;
    return PopupMenuButton<String>(
      tooltip: context.tr("hero.language"),
      onSelected: (String value) {
        context.setLanguageCode(value);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: "sw", child: Text(context.tr("lang.sw"))),
        PopupMenuItem<String>(value: "en", child: Text(context.tr("lang.en"))),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: compact
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: compact
                ? Theme.of(context).colorScheme.outlineVariant
                : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.language_rounded,
              size: 18,
              color: compact ? null : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              swahili ? "SW" : "EN",
              style: TextStyle(
                color: compact ? null : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicHomeData {
  const _PublicHomeData({
    required this.categories,
    required this.feed,
    required this.promotions,
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> feed;
  final List<Map<String, dynamic>> promotions;
}

class _PromotionBlock extends StatelessWidget {
  const _PromotionBlock({required this.promotions});

  final List<Map<String, dynamic>> promotions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: promotions.map((Map<String, dynamic> promotion) {
        final String? mediaType = promotion["media_type"] as String?;
        final String? mediaUrl = promotion["media_url"] as String?;
        final String? thumbnailUrl = promotion["thumbnail_url"] as String?;
        final String? mediaPath = promotion["media_path"] as String?;
        final String? thumbnailPath = promotion["thumbnail_path"] as String?;
        final String description = promotion["description"] as String? ?? "";
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(KodimaliRadii.card),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
            ),
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      KodimaliStatusBadge(
                        label: context.tr("promotion.label"),
                        tone: KodimaliStatusTone.info,
                      ),
                      const Spacer(),
                      Icon(
                        mediaType == "video"
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  if (mediaUrl != null) ...<Widget>[
                    const SizedBox(height: KodimaliSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(KodimaliRadii.card),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: mediaType == "video"
                            ? _TapToPlayPromotionVideo(
                                videoUrl: mediaUrl,
                                cacheKey: mediaPath ?? mediaUrl,
                                thumbnailUrl: thumbnailUrl,
                                thumbnailCacheKey:
                                    thumbnailPath ?? thumbnailUrl ?? mediaUrl,
                              )
                            : _NetworkMediaImage(
                                imageUrl: mediaUrl,
                                cacheKey: mediaPath ?? mediaUrl,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ],
                  const SizedBox(height: KodimaliSpacing.sm),
                  Text(
                    promotion["title"] as String? ??
                        context.tr("promotion.titleFallback"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: KodimaliSpacing.xs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: KodimaliSpacing.sm),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FullscreenImageScreen extends StatelessWidget {
  const _FullscreenImageScreen({
    required this.imageUrl,
    required this.cacheKey,
  });

  final String imageUrl;
  final String cacheKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: _NetworkMediaImage(
              imageUrl: imageUrl,
              cacheKey: cacheKey,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentSummaryCard extends StatelessWidget {
  const _AgentSummaryCard({required this.agentSummary});

  final Map<String, dynamic> agentSummary;

  @override
  Widget build(BuildContext context) {
    if (agentSummary.isEmpty) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final String displayName =
        agentSummary["display_name"] as String? ?? "Agent";
    final String? businessName = agentSummary["business_name"] as String?;
    final String locationLabel =
        agentSummary["location_label"] as String? ??
        context.tr("agent.locationUnknown");
    final bool verified =
        (agentSummary["verification_status"] as String?) == "approved";
    final String? profilePhotoUrl =
        agentSummary["profile_photo_url"] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KodimaliSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.tr("agent.title"), style: theme.textTheme.titleLarge),
            const SizedBox(height: KodimaliSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CustomerAgentAvatar(
                  imageUrl: profilePhotoUrl,
                  fallbackText: displayName,
                  verified: verified,
                ),
                const SizedBox(width: KodimaliSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              displayName,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (verified) const _VerifiedBadgeIcon(),
                        ],
                      ),
                      if (businessName != null &&
                          businessName.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          businessName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(locationLabel)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              context.tr("agent.phoneHidden"),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KodimaliSpacing.sm),
            KodimaliStatusBadge(
              label: verified
                  ? context.tr("agent.verified")
                  : context.tr("agent.unverified"),
              tone: verified
                  ? KodimaliStatusTone.active
                  : KodimaliStatusTone.pending,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerAgentAvatar extends StatelessWidget {
  const _CustomerAgentAvatar({
    required this.imageUrl,
    required this.fallbackText,
    required this.verified,
  });

  final String? imageUrl;
  final String fallbackText;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = CircleAvatar(
      radius: 28,
      backgroundImage: imageUrl == null || imageUrl!.isEmpty
          ? null
          : NetworkImage(imageUrl!),
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text((fallbackText.isEmpty ? "A" : fallbackText[0]).toUpperCase())
          : null,
    );
    if (!verified) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatar,
        const Positioned(right: -2, bottom: -2, child: _VerifiedBadgeIcon()),
      ],
    );
  }
}

class _CustomerLifecycleObserver extends WidgetsBindingObserver {
  _CustomerLifecycleObserver({required this.onResume});

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

class _VerifiedBadgeIcon extends StatelessWidget {
  const _VerifiedBadgeIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: const Color(0xFF1D9BF0),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
    );
  }
}

class _ListingAttributeItem {
  const _ListingAttributeItem({required this.label, required this.value});

  final String label;
  final String value;
}

List<_ListingAttributeItem> _buildListingAttributeItems({
  required BuildContext context,
  required Map<String, dynamic> attributes,
  required List<Map<String, dynamic>> fieldSchema,
}) {
  final List<_ListingAttributeItem> items = <_ListingAttributeItem>[];
  final Set<String> consumedKeys = <String>{};

  for (final Map<String, dynamic> field in fieldSchema) {
    final String key = field["key"] as String? ?? "";
    if (key.isEmpty || !attributes.containsKey(key)) {
      continue;
    }
    if (key == "land_size_unit" && attributes["land_size"] != null) {
      consumedKeys.add(key);
      continue;
    }
    final String? value = _formatListingAttributeValue(
      context: context,
      key: key,
      label: field["label"] as String? ?? _humanizeAttributeKey(key),
      type: field["type"] as String?,
      value: attributes[key],
      allAttributes: attributes,
    );
    consumedKeys.add(key);
    if (value == null || value.isEmpty) {
      continue;
    }
    items.add(
      _ListingAttributeItem(
        label: field["label"] as String? ?? _humanizeAttributeKey(key),
        value: value,
      ),
    );
  }

  for (final MapEntry<String, dynamic> entry in attributes.entries) {
    if (consumedKeys.contains(entry.key)) {
      continue;
    }
    if (entry.key == "land_size_unit" && attributes["land_size"] != null) {
      continue;
    }
    final String? value = _formatListingAttributeValue(
      context: context,
      key: entry.key,
      label: _humanizeAttributeKey(entry.key),
      value: entry.value,
      allAttributes: attributes,
    );
    if (value == null || value.isEmpty) {
      continue;
    }
    items.add(
      _ListingAttributeItem(
        label: _humanizeAttributeKey(entry.key),
        value: value,
      ),
    );
  }

  return items;
}

String? _formatListingAttributeValue({
  required BuildContext context,
  required String key,
  required String label,
  required dynamic value,
  required Map<String, dynamic> allAttributes,
  String? type,
}) {
  if (value == null) {
    return null;
  }
  if (key == "land_size") {
    final String unit = allAttributes["land_size_unit"]?.toString() ?? "";
    final String size = value.toString().trim();
    return unit.isEmpty ? size : "$size $unit";
  }
  if (value is List<dynamic>) {
    final String joined = value
        .map((dynamic item) => item.toString().trim())
        .where((String item) => item.isNotEmpty)
        .join(", ");
    return joined.isEmpty ? null : joined;
  }
  if (type == "boolean" || value is bool) {
    final bool enabled =
        value == true || value.toString().toLowerCase() == "true";
    if (key == "furnished") {
      return enabled
          ? context.tr("detail.furnishedYes")
          : context.tr("detail.furnishedNo");
    }
    if (label.toLowerCase().contains("included") || key.endsWith("_included")) {
      return enabled
          ? context.tr("detail.included")
          : context.tr("detail.notIncluded");
    }
    return enabled
        ? context.tr("detail.available")
        : context.tr("detail.unavailable");
  }
  final String text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String _humanizeAttributeKey(String key) {
  return key
      .split("_")
      .where((String part) => part.isNotEmpty)
      .map(
        (String part) =>
            "${part[0].toUpperCase()}${part.substring(1).toLowerCase()}",
      )
      .join(" ");
}

IconData _categoryIconForSlug(String slug) {
  switch (slug) {
    case "house":
      return Icons.house_rounded;
    case "car":
      return Icons.directions_car_filled_rounded;
    case "motorcycle":
      return Icons.two_wheeler_rounded;
    case "office":
      return Icons.business_center_rounded;
    case "meeting-hall":
    case "ceremony-hall":
      return Icons.celebration_rounded;
    case "equipment":
      return Icons.handyman_rounded;
    case "farms":
      return Icons.agriculture_rounded;
    default:
      return Icons.category_rounded;
  }
}

class _FarmHighlights extends StatelessWidget {
  const _FarmHighlights({required this.categorySlug, required this.attributes});

  final String? categorySlug;
  final Map<String, dynamic> attributes;

  @override
  Widget build(BuildContext context) {
    if (categorySlug != "farms") {
      return const SizedBox.shrink();
    }

    final String waterAvailability =
        attributes["water_availability"]?.toString() ?? "-";
    final String bestCrops = switch (attributes["best_crops"]) {
      List<dynamic> values =>
        values.map((dynamic value) => value.toString()).join(", "),
      final Object? value => value?.toString() ?? "-",
    };
    final String landSize = [
      attributes["land_size"]?.toString(),
      attributes["land_size_unit"]?.toString(),
    ].whereType<String>().where((String value) => value.isNotEmpty).join(" ");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.tr("farm.highlights"),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _HighlightTile(
          label: context.tr("farm.water"),
          value: waterAvailability,
        ),
        const SizedBox(height: 8),
        _HighlightTile(
          label: context.tr("farm.crops"),
          value: bestCrops.isEmpty ? "-" : bestCrops,
        ),
        const SizedBox(height: 8),
        _HighlightTile(
          label: context.tr("farm.size"),
          value: landSize.isEmpty ? "-" : landSize,
        ),
      ],
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _TapToPlayPromotionVideo extends StatefulWidget {
  const _TapToPlayPromotionVideo({
    required this.videoUrl,
    required this.cacheKey,
    this.thumbnailUrl,
    this.thumbnailCacheKey,
  });

  final String videoUrl;
  final String cacheKey;
  final String? thumbnailUrl;
  final String? thumbnailCacheKey;

  @override
  State<_TapToPlayPromotionVideo> createState() =>
      _TapToPlayPromotionVideoState();
}

class _TapToPlayPromotionVideoState extends State<_TapToPlayPromotionVideo> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;
  bool _muted = true;

  Future<void> _initialize() async {
    final File mediaFile = await CustomerMediaCacheManager.instance
        .getSingleFile(widget.videoUrl, key: widget.cacheKey);
    final VideoPlayerController controller = VideoPlayerController.file(
      mediaFile,
    );
    _controller = controller;
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(0);
    await controller.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      final Future<void> initialization = _initialize();
      setState(() {
        _initialization = initialization;
      });
      await initialization;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleMuted() async {
    _muted = !_muted;
    await _controller?.setVolume(_muted ? 0 : 1);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (widget.thumbnailUrl != null)
          _NetworkMediaImage(
            imageUrl: widget.thumbnailUrl,
            cacheKey:
                widget.thumbnailCacheKey ??
                widget.thumbnailUrl ??
                widget.videoUrl,
            fit: BoxFit.cover,
          )
        else
          Container(color: Colors.black12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
        ),
      ],
    );

    return FutureBuilder<void>(
      future: _initialization,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        final VideoPlayerController? controller = _controller;
        if (_initialization == null) {
          return GestureDetector(onTap: _togglePlayPause, child: placeholder);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return placeholder;
        }
        if (snapshot.hasError || controller == null) {
          return GestureDetector(onTap: _togglePlayPause, child: placeholder);
        }

        return GestureDetector(
          onTap: _togglePlayPause,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.10),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.38),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.tr("media.tapToPlay"),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Row(
                  children: <Widget>[
                    _MediaActionButton(
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onTap: _toggleMuted,
                    ),
                    const SizedBox(width: 8),
                    _MediaActionButton(
                      icon: controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: _togglePlayPause,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
