import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import 'verified_badge.dart';

/// 头像组件：支持网络图、默认占位、尺寸、认证徽章、点击回调。
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.url,
    this.size = 40,
    this.verified = false,
    this.onTap,
    this.borderColor,
  });

  final String url;
  final double size;
  final bool verified;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final child = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? Container(
                color: colors.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: size * 0.6,
                  color: colors.outline,
                ),
              )
            : CachedNetworkImage(
                imageUrl: getFullImageUrl(url),
                fit: BoxFit.cover,
                memCacheWidth: (size * 2).toInt(),
                placeholder: (_, __) =>
                    Container(color: colors.surfaceContainerHighest),
                errorWidget: (_, __, ___) => Container(
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: colors.outline,
                  ),
                ),
              ),
      ),
    );

    final avatar = borderColor != null
        ? Container(
            padding: EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor!, width: 1.5),
            ),
            child: child,
          )
        : child;

    if (!verified) {
      return onTap == null
          ? avatar
          : GestureDetector(onTap: onTap, child: avatar);
    }

    final badge = const VerifiedBadge(size: 14);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(right: -2, bottom: -2, child: badge),
          ],
        ),
      ),
    );
  }
}
