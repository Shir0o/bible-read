import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AuthBackground extends StatelessWidget {
  final WidgetBuilder builder;

  const AuthBackground({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    const colorScheme = AppTheme.designDarkScheme;

    return Theme(
      data: AppTheme.appTheme(colorScheme),
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;

          return Scaffold(
            backgroundColor: colors.surface,
            body: Stack(
              children: [
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: AppTheme.authHeroImageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        ColoredBox(color: colors.surface),
                    errorWidget: (context, url, error) =>
                        ColoredBox(color: colors.surface),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colors.surface,
                          colors.surface.withValues(alpha: 0.88),
                          colors.surface.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colors.scrim.withValues(alpha: 0.72),
                          colors.scrim.withValues(alpha: 0.36),
                          colors.scrim.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.35, 1],
                      ),
                    ),
                  ),
                ),
                SafeArea(child: builder(context)),
              ],
            ),
          );
        },
      ),
    );
  }
}
