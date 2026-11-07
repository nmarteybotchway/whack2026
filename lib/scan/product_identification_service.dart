import 'dart:convert';
import 'dart:typed_data';

import '../foodbase/foodbase_api.dart';
import '../openrouter.dart';
import '../secrets.dart' show foodBaseApiKey;

/// Selects which backend handles product identification.
enum ProductIdentificationBackend {
  openRouter,
  api;

  static ProductIdentificationBackend fromStoredValue(Object? value) =>
      value == ProductIdentificationBackend.api.name
      ? ProductIdentificationBackend.api
      : value == ProductIdentificationBackend.openRouter.name
      ? ProductIdentificationBackend.openRouter
      : ProductIdentificationBackend.api;
}

/// Product details read or recognized from the photographed package.
///
/// SKU and GTIN are kept separate: a SKU is seller-specific, while a GTIN is
/// the number encoded by a retail barcode. Either stays null unless the image
/// provides direct evidence for it.
class ProductIdentification {
  const ProductIdentification({
    required this.status,
    required this.productName,
    required this.brand,
    required this.variant,
    required this.packageSize,
    required this.sku,
    required this.gtin,
    this.catalogProductId,
    required this.confidence,
    required this.productNameConfidence,
    required this.brandConfidence,
    required this.variantConfidence,
    required this.skuConfidence,
    required this.gtinConfidence,
    required this.evidence,
    required this.uncertainties,
  });

  final String status;
  final String? productName;
  final String? brand;
  final String? variant;
  final String? packageSize;
  final String? sku;
  final String? gtin;
  final String? catalogProductId;
  final int confidence;
  final int productNameConfidence;
  final int brandConfidence;
  final int variantConfidence;
  final int skuConfidence;
  final int gtinConfidence;
  final List<String> evidence;
  final List<String> uncertainties;

  String get displayName {
    final brandTokens =
        brand
            ?.toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((token) => token.isNotEmpty)
            .toList() ??
        const <String>[];
    final nameTokens =
        productName
            ?.toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((token) => token.isNotEmpty)
            .toSet() ??
        const <String>{};
    final brandAlreadyInName =
        brandTokens.isNotEmpty && brandTokens.every(nameTokens.contains);
    final normalizedName = productName?.toLowerCase() ?? '';
    final variantValue = variant;
    final packageSizeValue = packageSize;
    return [
      if (brand != null && !brandAlreadyInName) brand!,
      ?productName,
      if (variantValue != null &&
          !normalizedName.contains(variantValue.toLowerCase()))
        variantValue,
      if (packageSizeValue != null &&
          !normalizedName.contains(packageSizeValue.toLowerCase()))
        packageSizeValue,
    ].join(' ');
  }

  factory ProductIdentification.fromJson(Map<String, dynamic> json) {
    String? optionalString(String key) {
      final value = json[key];
      if (value == null) {
        return null;
      }
      if (value is! String) {
        throw FormatException('$key must be a string or null');
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    int? parseConfidence(Object? value) {
      final parsed = value is num
          ? value
          : value is String
          ? num.tryParse(value.trim().replaceAll('%', ''))
          : null;
      if (parsed == null || parsed < 0 || parsed > 100) return null;
      if (parsed is double && parsed <= 1) return (parsed * 100).round();
      return parsed.round();
    }

    List<String> stringList(String key) {
      final value = json[key];
      if (value is List) {
        return value.whereType<String>().toList();
      }
      if (value is Map) {
        return value.entries
            .where((entry) => entry.value is String)
            .map((entry) => '${entry.key}: ${entry.value}')
            .toList();
      }
      return const [];
    }

    final rawConfidence = json['confidence'];
    final confidenceMap = rawConfidence is Map
        ? rawConfidence.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};

    int fieldConfidence(String field) =>
        parseConfidence(json['${field}_confidence']) ??
        parseConfidence(confidenceMap[field]) ??
        0;

    final parsedOverall =
        parseConfidence(rawConfidence) ??
        parseConfidence(confidenceMap['overall']) ??
        parseConfidence(confidenceMap['overall_confidence']);
    final availableFieldConfidences = [
      for (final field in const [
        'product_name',
        'brand',
        'variant',
        'package_size',
        'sku',
        'gtin',
      ])
        ?parseConfidence(confidenceMap[field]),
    ];
    final overallConfidence =
        parsedOverall ??
        (availableFieldConfidences.isEmpty
            ? 0
            : (availableFieldConfidences.reduce((a, b) => a + b) /
                      availableFieldConfidences.length)
                  .round());

    final status = json['status'];
    if (status is! String ||
        !const {
          'identified',
          'ambiguous',
          'unreadable',
          'not_a_product',
        }.contains(status)) {
      throw const FormatException('status has an unsupported value');
    }

    final product = ProductIdentification(
      status: status,
      productName: optionalString('product_name'),
      brand: optionalString('brand'),
      variant: optionalString('variant'),
      packageSize: optionalString('package_size'),
      sku: optionalString('sku'),
      gtin: optionalString('gtin'),
      catalogProductId: optionalString('catalog_product_id'),
      confidence: overallConfidence,
      productNameConfidence: fieldConfidence('product_name'),
      brandConfidence: fieldConfidence('brand'),
      variantConfidence: fieldConfidence('variant'),
      skuConfidence: fieldConfidence('sku'),
      gtinConfidence: fieldConfidence('gtin'),
      evidence: stringList('evidence'),
      uncertainties: stringList('uncertainties'),
    );
    if (product.status == 'identified' && product.productName == null) {
      throw const FormatException(
        'An identified product must include a product name',
      );
    }
    return product;
  }
}

/// Contract shared by the available identification backends.
abstract interface class ProductIdentificationProvider {
  Future<ProductIdentification> identify(Uint8List jpegBytes);

  void close();
}

/// Identifies the exact packaged item visible in a camera photo.
class ProductIdentificationService implements ProductIdentificationProvider {
  ProductIdentificationService({OpenRouterService? openRouter})
    : _openRouter = openRouter ?? OpenRouterService();

  final OpenRouterService _openRouter;

  static const Map<String, Object?> _responseSchema = {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['identified', 'ambiguous', 'unreadable', 'not_a_product'],
      },
      'product_name': {
        'type': ['string', 'null'],
      },
      'brand': {
        'type': ['string', 'null'],
      },
      'variant': {
        'type': ['string', 'null'],
      },
      'package_size': {
        'type': ['string', 'null'],
      },
      'sku': {
        'type': ['string', 'null'],
      },
      'gtin': {
        'type': ['string', 'null'],
      },
      'confidence': {'type': 'integer', 'minimum': 0, 'maximum': 100},
      'product_name_confidence': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 100,
      },
      'brand_confidence': {'type': 'integer', 'minimum': 0, 'maximum': 100},
      'variant_confidence': {'type': 'integer', 'minimum': 0, 'maximum': 100},
      'sku_confidence': {'type': 'integer', 'minimum': 0, 'maximum': 100},
      'gtin_confidence': {'type': 'integer', 'minimum': 0, 'maximum': 100},
      'evidence': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'uncertainties': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': [
      'status',
      'product_name',
      'brand',
      'variant',
      'package_size',
      'sku',
      'gtin',
      'confidence',
      'product_name_confidence',
      'brand_confidence',
      'variant_confidence',
      'sku_confidence',
      'gtin_confidence',
      'evidence',
      'uncertainties',
    ],
    'additionalProperties': false,
  };

  static const _prompt = '''
Identify the exact packaged consumer product shown in this photo. The user needs
the specific product, brand, variant, package size, and any product identifiers.

Carefully inspect visible front and back packaging text. Transcribe printed
names and numbers as shown. Do not guess, complete, or invent obscured details.
SKU is seller-specific: return it only if an SKU is explicitly printed in the
image. Return GTIN only when the barcode digits themselves are clearly readable;
do not derive barcode digits from the bars or guess from memory. If the image
does not show enough evidence, use null for that field and explain what is
missing under uncertainties. A product can still be identified when some
identifier fields are null.

Use a concise, recognizable product name (for example, "Mini Chocolate
Fingers"). Put the maker/brand in brand, product type/name in product_name,
flavour or product-line distinctions in variant, and printed net quantity in
package_size. Confidence values are 0-100 and must reflect visual evidence for
each individual field, not how familiar the product seems. Include short visual
observations in evidence. Return status "identified" only if the specific item
is distinguishable, "ambiguous" if multiple products could match,
"unreadable" if packaging is too unclear, or "not_a_product" if no packaged
consumer product is present.
''';

  @override
  Future<ProductIdentification> identify(Uint8List jpegBytes) async {
    final response = await _openRouter.generate(
      prompt: _prompt,
      image: OpenRouterImage(jpegBytes),
      responseSchema: _responseSchema,
    );
    final decoded = _decodeJsonObject(response);
    final result = ProductIdentification.fromJson(decoded);

    // Do not present fabricated identifiers if a model violates the prompt.
    final gtin = result.gtin;
    if (gtin != null && !_isValidGtin(gtin)) {
      throw const FormatException('GTIN has an invalid length or check digit');
    }
    return result;
  }

  Map<String, dynamic> _decodeJsonObject(String response) {
    final candidates = <String>[response.trim()];
    final fences = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in fences.allMatches(response)) {
      final fencedJson = match.group(1)?.trim();
      if (fencedJson != null) candidates.add(fencedJson);
    }
    final object = _firstJsonObject(response);
    if (object != null) candidates.add(object);

    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Try the next candidate: some models wrap JSON in Markdown.
      }
    }
    final table = _decodeIdentificationTable(response);
    if (table != null) return table;
    final normalized = response.trim().replaceAll('\n', ' ');
    final excerpt = normalized.substring(
      0,
      normalized.length < 300 ? normalized.length : 300,
    );
    throw FormatException(
      'OpenRouter did not return a JSON product identification object. '
      'Response starts: $excerpt',
    );
  }

  Map<String, dynamic>? _decodeIdentificationTable(String response) {
    final lines = response.split('\n').map((line) => line.trim()).toList();
    for (var index = 0; index + 1 < lines.length; index++) {
      final headers = _markdownCells(lines[index]);
      if (headers.length < 2 ||
          !headers.any((header) => header.toLowerCase() == 'field') ||
          !headers.any((header) => header.toLowerCase() == 'value')) {
        continue;
      }
      final fieldColumn = headers.indexWhere(
        (header) => header.toLowerCase() == 'field',
      );
      final valueColumn = headers.indexWhere(
        (header) => header.toLowerCase() == 'value',
      );
      final confidenceColumn = headers.indexWhere(
        (header) => header.toLowerCase().contains('confidence'),
      );
      final evidenceColumn = headers.indexWhere(
        (header) => header.toLowerCase().contains('evidence'),
      );
      if (!_isMarkdownSeparator(lines[index + 1])) continue;

      final fields = <String, dynamic>{'status': 'identified'};
      final confidence = <String, dynamic>{};
      final evidence = <String, String>{};
      for (final line in lines.skip(index + 2)) {
        if (!line.startsWith('|')) break;
        final cells = _markdownCells(line);
        if (cells.length <= fieldColumn || cells.length <= valueColumn) {
          continue;
        }
        final key = _normalizeTableField(cells[fieldColumn]);
        if (key == null) continue;
        final rawValue = cells[valueColumn].trim();
        final value = _emptyTableValue(rawValue) ? null : rawValue;
        if (key == 'status') {
          fields['status'] = value?.toLowerCase() ?? 'unreadable';
        } else if (key == 'evidence' || key == 'uncertainties') {
          fields[key] = value == null ? <String>[] : [value];
        } else {
          fields[key] = value;
        }
        if (confidenceColumn >= 0 && confidenceColumn < cells.length) {
          final score = cells[confidenceColumn].trim();
          if (!_emptyTableValue(score)) confidence[key] = score;
        }
        if (evidenceColumn >= 0 && evidenceColumn < cells.length) {
          final detail = cells[evidenceColumn].trim();
          if (!_emptyTableValue(detail)) evidence[key] = detail;
        }
      }
      if (fields['product_name'] == null) return null;
      if (confidence.isNotEmpty) fields['confidence'] = confidence;
      if (evidence.isNotEmpty) fields['evidence'] = evidence;
      return fields;
    }
    return null;
  }

  List<String> _markdownCells(String row) {
    final trimmed = row
        .trim()
        .replaceFirst(RegExp(r'^\|'), '')
        .replaceFirst(RegExp(r'\|$'), '');
    return trimmed.split('|').map((cell) => cell.trim()).toList();
  }

  bool _isMarkdownSeparator(String row) =>
      row.startsWith('|') &&
      RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$').hasMatch(row);

  bool _emptyTableValue(String value) =>
      value.isEmpty ||
      const {
        '-',
        'n/a',
        'not visible',
        'unknown',
        'null',
      }.contains(value.toLowerCase());

  String? _normalizeTableField(String label) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    const aliases = <String, String>{
      'status': 'status',
      'brand': 'brand',
      'product': 'product_name',
      'product name': 'product_name',
      'item': 'product_name',
      'item name': 'product_name',
      'variant': 'variant',
      'flavour': 'variant',
      'flavor': 'variant',
      'package size': 'package_size',
      'pack size': 'package_size',
      'size': 'package_size',
      'sku': 'sku',
      'gtin': 'gtin',
      'ean': 'gtin',
      'upc': 'gtin',
      'barcode': 'gtin',
      'catalog product id': 'catalog_product_id',
      'catalog id': 'catalog_product_id',
      'evidence': 'evidence',
      'uncertainties': 'uncertainties',
    };
    return aliases[normalized];
  }

  String? _firstJsonObject(String source) {
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;

    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        if (depth == 0) start = index;
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          return source.substring(start, index + 1);
        }
      }
    }
    return null;
  }

  bool _isValidGtin(String value) {
    if (!const {8, 12, 13, 14}.contains(value.length) ||
        !RegExp(r'^\d+$').hasMatch(value)) {
      return false;
    }

    var sum = 0;
    var weight = 3;
    for (var index = value.length - 2; index >= 0; index--) {
      sum += int.parse(value[index]) * weight;
      weight = weight == 3 ? 1 : 3;
    }
    final checkDigit = (10 - sum % 10) % 10;
    return checkDigit == int.parse(value[value.length - 1]);
  }

  @override
  void close() => _openRouter.close();
}

/// FoodBase backend for product-photo identification.
class ApiProductIdentification implements ProductIdentificationProvider {
  const ApiProductIdentification();

  @override
  Future<ProductIdentification> identify(Uint8List jpegBytes) async {
    if (foodBaseApiKey.trim().isEmpty) {
      return const ProductIdentification(
        status: 'unavailable',
        productName: null,
        brand: null,
        variant: null,
        packageSize: null,
        sku: null,
        gtin: null,
        confidence: 0,
        productNameConfidence: 0,
        brandConfidence: 0,
        variantConfidence: 0,
        skuConfidence: 0,
        gtinConfidence: 0,
        evidence: [],
        uncertainties: ['FoodBase API key is not configured.'],
      );
    }

    final response = await identifyFoodProduct(
      imageBytes: jpegBytes,
      filename: 'product-scan.jpg',
      apiKey: foodBaseApiKey,
    );
    return _fromFoodBaseResponse(response);
  }

  ProductIdentification _fromFoodBaseResponse(Map<String, dynamic> response) {
    final extracted = _asMap(response['extracted']) ?? const {};
    final matches = response['matches'];
    Map<String, dynamic>? bestMatch;
    Map<String, dynamic>? product;
    if (matches is List) {
      for (final candidate in matches) {
        final parsedCandidate = _asMap(candidate);
        final parsedProduct = _asMap(parsedCandidate?['product']);
        if (parsedCandidate != null && parsedProduct != null) {
          bestMatch = parsedCandidate;
          product = parsedProduct;
          break;
        }
      }
    }

    final productName =
        _readString(product, const ['name_default', 'name']) ??
        _readString(extracted, const ['name']);
    final brand =
        _readString(product, const ['brand']) ??
        _readString(extracted, const ['brand']);
    final variant = _readString(product, const [
      'variant',
      'flavor',
      'flavour',
    ]);
    final packageSize =
        _readString(product, const ['quantity', 'package_size']) ??
        _readString(extracted, const ['quantity']);
    final sku = _readString(product, const ['sku']);
    final rawGtin = _readString(product, const [
      'gtin',
      'barcode',
      'ean',
      'upc',
    ]);
    final gtin = rawGtin != null && _isValidGtin(rawGtin) ? rawGtin : null;
    final catalogProductId = _readString(product, const ['id']);
    final score =
        _asNumber(bestMatch?['score']) ??
        _asNumber(extracted['confidence']) ??
        0;
    final confidence = _toPercent(score);
    final hasCatalogMatch = product != null;

    return ProductIdentification(
      status: productName == null
          ? 'unreadable'
          : hasCatalogMatch
          ? 'identified'
          : 'ambiguous',
      productName: productName,
      brand: brand,
      variant: variant,
      packageSize: packageSize,
      sku: sku,
      gtin: gtin,
      catalogProductId: catalogProductId,
      confidence: confidence,
      productNameConfidence: confidence,
      brandConfidence: brand == null ? 0 : confidence,
      variantConfidence: variant == null ? 0 : confidence,
      skuConfidence: sku == null ? 0 : 100,
      gtinConfidence: gtin == null ? 0 : 100,
      evidence: [
        if (brand != null) 'Brand read or matched: $brand',
        if (productName != null) 'Product name read or matched: $productName',
        if (catalogProductId != null)
          'FoodBase catalog product: $catalogProductId',
      ],
      uncertainties: [
        if (!hasCatalogMatch && productName != null)
          'No matching catalog record was returned.',
        if (sku == null) 'No SKU was returned by the product catalog.',
        if (gtin == null)
          'No verified GTIN was returned by the product catalog.',
      ],
    );
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String? _readString(Map<String, dynamic>? source, List<String> keys) {
    if (source == null) return null;
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  num? _asNumber(Object? value) => value is num ? value : null;

  int _toPercent(num value) => (value.clamp(0, 1) * 100).round();

  bool _isValidGtin(String value) {
    if (!const {8, 12, 13, 14}.contains(value.length) ||
        !RegExp(r'^\d+$').hasMatch(value)) {
      return false;
    }
    var sum = 0;
    var weight = 3;
    for (var index = value.length - 2; index >= 0; index--) {
      sum += int.parse(value[index]) * weight;
      weight = weight == 3 ? 1 : 3;
    }
    return (10 - sum % 10) % 10 == int.parse(value[value.length - 1]);
  }

  @override
  void close() {}
}
