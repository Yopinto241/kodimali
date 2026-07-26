import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CustomerMediaCacheManager extends CacheManager {
  CustomerMediaCacheManager._()
    : super(
        Config(
          _cacheKey,
          stalePeriod: const Duration(hours: 12),
          maxNrOfCacheObjects: 80,
        ),
      );

  static const String _cacheKey = "kodimaliCustomerMediaCache";

  static final CustomerMediaCacheManager instance =
      CustomerMediaCacheManager._();
}
