import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CustomerMediaCacheManager extends CacheManager {
  CustomerMediaCacheManager._()
    : super(
        Config(
          _cacheKey,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 250,
        ),
      );

  static const String _cacheKey = "kodimaliCustomerMediaCache";

  static final CustomerMediaCacheManager instance =
      CustomerMediaCacheManager._();
}
