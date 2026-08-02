import '../../../shared/domain/post_entity.dart';
import 'post_dto.dart';

class CreatePostRequest {
  const CreatePostRequest({
    required this.title,
    required this.content,
    required this.type,
    this.categoryId,
    this.tags = const [],
    this.images = const [],
    this.videoUrl,
    this.coverUrl,
    this.isDraft = false,
    this.location,
  });

  final String title;
  final String content;
  final int type; 
  final int? categoryId;
  final List<String> tags;
  final List<String> images;
  final String? videoUrl;
  final String? coverUrl;
  final bool isDraft;
  final String? location;

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'type': type,
    if (categoryId != null) 'category_id': categoryId,
    'tags': tags,
    'images': images,
    if (videoUrl != null) 'video_url': videoUrl,
    if (coverUrl != null) 'cover_url': coverUrl,
    'is_draft': isDraft ? 1 : 0,
    if (location != null) 'location': location,
  };
}

class DraftEntity {
  const DraftEntity({
    this.id,
    required this.title,
    required this.content,
    required this.type,
    this.categoryId,
    this.tags = const [],
    this.localImages = const [],
    this.localVideo,
    this.remoteImages = const [],
    this.remoteVideoUrl,
    this.remoteCoverUrl,
    this.location,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String content;
  final int type;
  final int? categoryId;
  final List<String> tags;
  final List<String> localImages;
  final String? localVideo;
  final List<String> remoteImages;
  final String? remoteVideoUrl;
  final String? remoteCoverUrl;
  final String? location;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'title': title,
    'content': content,
    'type': type,
    if (categoryId != null) 'category_id': categoryId,
    'tags': tags,
    'local_images': localImages,
    if (localVideo != null) 'local_video': localVideo,
    'remote_images': remoteImages,
    if (remoteVideoUrl != null) 'remote_video_url': remoteVideoUrl,
    if (remoteCoverUrl != null) 'remote_cover_url': remoteCoverUrl,
    if (location != null) 'location': location,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory DraftEntity.fromJson(Map<String, dynamic> json) {
    return DraftEntity(
      id: json['id'] as int?,
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      type: (json['type'] as num?)?.toInt() ?? 1,
      categoryId: (json['category_id'] as num?)?.toInt(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      localImages: (json['local_images'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      localVideo: json['local_video'] as String?,
      remoteImages: (json['remote_images'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      remoteVideoUrl: json['remote_video_url'] as String?,
      remoteCoverUrl: json['remote_cover_url'] as String?,
      location: json['location'] as String?,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  DraftEntity copyWith({
    int? id,
    String? title,
    String? content,
    int? type,
    int? categoryId,
    List<String>? tags,
    List<String>? localImages,
    String? localVideo,
    List<String>? remoteImages,
    String? remoteVideoUrl,
    String? remoteCoverUrl,
    String? location,
    DateTime? updatedAt,
  }) {
    return DraftEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      tags: tags ?? this.tags,
      localImages: localImages ?? this.localImages,
      localVideo: localVideo ?? this.localVideo,
      remoteImages: remoteImages ?? this.remoteImages,
      remoteVideoUrl: remoteVideoUrl ?? this.remoteVideoUrl,
      remoteCoverUrl: remoteCoverUrl ?? this.remoteCoverUrl,
      location: location ?? this.location,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isEmpty =>
      title.isEmpty &&
      content.isEmpty &&
      localImages.isEmpty &&
      remoteImages.isEmpty &&
      localVideo == null &&
      remoteVideoUrl == null;
}

class PublishResultEntity {
  const PublishResultEntity({required this.id, required this.title});

  final int id;
  final String title;

  static PublishResultEntity fromDto(PostDto dto) =>
      PublishResultEntity(id: dto.id, title: dto.title);
}

typedef PublishCategoryEntity = CategoryEntity;
