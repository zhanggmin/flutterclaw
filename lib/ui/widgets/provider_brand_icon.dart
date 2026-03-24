import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutterclaw/data/models/model_catalog.dart';

/// Shows a bundled SVG brand mark when [CatalogProvider.logoAsset] is set,
/// otherwise [CatalogProvider.icon]. If [provider] is null, uses [fallbackIcon].
class ProviderBrandIcon extends StatelessWidget {
  const ProviderBrandIcon({
    super.key,
    required this.provider,
    required this.size,
    this.iconColor,
    this.fallbackIcon = Icons.smart_toy,
  });

  final CatalogProvider? provider;
  final double size;
  final Color? iconColor;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final color =
        iconColor ?? Theme.of(context).colorScheme.onSurface;
    final p = provider;
    if (p == null) {
      return Icon(fallbackIcon, size: size, color: color);
    }
    final asset = p.logoAsset;
    if (asset == null || asset.isEmpty) {
      return Icon(p.icon, size: size, color: color);
    }
    final pad = size * 0.14;
    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: SvgPicture.asset(
          asset,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          errorBuilder: (context, error, stackTrace) =>
              Icon(p.icon, size: size, color: color),
        ),
      ),
    );
  }
}
