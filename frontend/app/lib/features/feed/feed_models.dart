class ProductCardData {
  const ProductCardData({
    required this.id,
    required this.referenceCode,
    required this.title,
    required this.imageUrl,
    required this.category,
    required this.brand,
    required this.minQty,
    required this.maxQty,
    required this.priceMin,
    required this.priceMax,
    this.weightKg = 0,
    required this.sellerId,
    required this.sellerReferenceCode,
    required this.sellerDisplayName,
    this.sellerAvatarUrl = "",
    required this.sellerCountryCode,
    this.sellerCity = "",
    this.sellerLocationLabel = "",
    this.sellerLatitude,
    this.sellerLongitude,
    required this.sellerVerified,
    required this.sellerTrustScore,
    required this.allowsGrouping,
    this.description = "",
    this.videoUrl,
  });

  final int id;
  final String referenceCode;
  final String title;
  final String imageUrl;
  final String category;
  final String brand;
  final int minQty;
  final int maxQty;
  final int priceMin;
  final int priceMax;
  final double weightKg;
  final int sellerId;
  final String sellerReferenceCode;
  final String sellerDisplayName;
  final String sellerAvatarUrl;
  final String sellerCountryCode;
  final String sellerCity;
  final String sellerLocationLabel;
  final double? sellerLatitude;
  final double? sellerLongitude;
  final bool sellerVerified;
  final double sellerTrustScore;
  final bool allowsGrouping;
  final String description;
  final String? videoUrl;
}

class CommentData {
  const CommentData({
    required this.author,
    required this.message,
    required this.timeLabel,
  });

  final String author;
  final String message;
  final String timeLabel;
}

class VideoPostData {
  const VideoPostData({
    required this.id,
    required this.coverUrl,
    required this.publisherName,
    required this.publisherAvatar,
    required this.description,
    required this.likes,
    required this.comments,
    required this.sellerId,
    this.videoUrl,
  });

  final int id;
  final String coverUrl;
  final String publisherName;
  final String publisherAvatar;
  final String description;
  final int likes;
  final List<CommentData> comments;
  final int sellerId;
  final String? videoUrl;
}
