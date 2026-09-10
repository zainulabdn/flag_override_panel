import 'package:flag_override_panel/flag_override_panel.dart';

/// Swaps the product list for the rebuilt version.
const BoolFlag newProductList = BoolFlag(
  'new_product_list',
  description: 'Show the rebuilt product list',
  group: 'Catalogue',
);

/// How many products to request per page.
const IntFlag pageSize = IntFlag(
  'page_size',
  defaultValue: 10,
  description: 'Products fetched per page',
  group: 'Catalogue',
);

/// Corner radius applied to product cards.
const DoubleFlag cardRadius = DoubleFlag(
  'card_radius',
  defaultValue: 12,
  description: 'Corner radius of a product card',
  group: 'Catalogue',
);

/// Which theme the app renders with.
const StringFlag themeMode = StringFlag(
  'theme_mode',
  defaultValue: 'system',
  options: <String>['system', 'light', 'dark'],
  description: 'Overrides the platform theme',
  group: 'Appearance',
);

/// The backend the app talks to.
const StringFlag apiHost = StringFlag(
  'api_host',
  defaultValue: 'https://api.example.com',
  description: 'Base URL for API calls',
  group: 'Networking',
);

/// Every flag the app knows about.
const List<Flag<Object>> appFlags = <Flag<Object>>[
  newProductList,
  pageSize,
  cardRadius,
  themeMode,
  apiHost,
];
