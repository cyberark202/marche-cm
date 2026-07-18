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
    this.posterUrl,
    this.videoLikesCount = 0,
    this.videoCommentsCount = 0,
    this.videoViewsCount = 0,
    this.isVideoLiked = false,
    this.isFollowingSeller = false,
    this.isFavorited = false,
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
  // Poster (vignette) extrait de la video cote backend ; image d'attente.
  final String? posterUrl;
  // Compteurs + états utilisateur du feed vidéo, embarqués par le backend
  // (annotations serveur) — évite un appel HTTP par vidéo affichée.
  final int videoLikesCount;
  final int videoCommentsCount;
  final int videoViewsCount;
  final bool isVideoLiked;
  final bool isFollowingSeller;
  final bool isFavorited;
}

class VideoPostData {
  const VideoPostData({
    required this.id,
    required this.coverUrl,
    required this.publisherName,
    required this.publisherAvatar,
    required this.description,
    required this.likes,
    required this.commentsCount,
    required this.views,
    required this.isLiked,
    required this.isFollowingSeller,
    required this.sellerId,
    required this.product,
    this.videoUrl,
  });

  final int id;
  final String coverUrl;
  final String publisherName;
  final String publisherAvatar;
  final String description;
  final int likes;
  final int commentsCount;
  final int views;
  final bool isLiked;
  final bool isFollowingSeller;
  final int sellerId;
  // Fiche produit liée : CTA « voir le produit » du feed (pattern TikTok Shop).
  final ProductCardData product;
  final String? videoUrl;
}
