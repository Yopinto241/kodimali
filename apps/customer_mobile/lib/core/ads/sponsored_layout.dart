const listingsPerSponsoredCard = 3;

({List<Map<String, dynamic>> inline, List<Map<String, dynamic>> remaining})
sponsoredLayout(List<Map<String, dynamic>> promotions, int listingCount) {
  final unique = <String, Map<String, dynamic>>{};
  for (final promotion in promotions) {
    unique[promotion['promotion_id'].toString()] = promotion;
  }
  final slots = listingCount > 0
      ? (listingCount - 1) ~/ listingsPerSponsoredCard
      : 0;
  final ads = unique.values.toList();
  return (
    inline: ads.take(slots).toList(),
    remaining: ads.skip(slots).toList(),
  );
}
