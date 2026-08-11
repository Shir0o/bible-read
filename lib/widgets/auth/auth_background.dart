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
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: MediaQuery.sizeOf(context).height * 0.57,
                  child: Image.asset(
                    AppTheme.authHeroAssetPath,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, 0.24),
                    errorBuilder: (context, error, stackTrace) =>
                        CachedNetworkImage(
                      imageUrl: AppTheme.authHeroImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          ColoredBox(color: colors.surface),
                      errorWidget: (context, url, error) =>
                          ColoredBox(color: colors.surface),
                    ),
                  ),
                ),
                // Veil confined to the hero band (design: auth.jsx AuthHero).
                // It fades the photograph into the page background so there is
                // no hard edge where the image band ends.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: MediaQuery.sizeOf(context).height * 0.57,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.surface.withValues(alpha: 0.22),
                          colors.surface.withValues(alpha: 0.04),
                          colors.surface.withValues(alpha: 0),
                          colors.surface.withValues(alpha: 0.55),
                          colors.surface,
                        ],
                        stops: const [0.0, 0.22, 0.62, 0.86, 1.0],
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
