# Image Caching

Badge images fetched over the network are cached on device using the
[`cached_network_image`](https://pub.dev/packages/cached_network_image)
package. Caching reduces bandwidth and speeds up repeated loads.

## Clearing the Cache

To remove a single badge from the cache:

```dart
CachedNetworkImage.evictFromCache(badgeUrl);
```

To clear all cached images:

```dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

await DefaultCacheManager().emptyCache();
```

These calls can be useful if badge artwork changes or storage must be
released.
