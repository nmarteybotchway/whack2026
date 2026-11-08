import 'dart:typed_data';

import '../foodbase/foodbase_api.dart';
import '../secrets.dart' show foodBaseApiKey;

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

  Map<String, Object?> toJson() => {
    'status': status,
    'product_name': productName,
    'brand': brand,
    'variant': variant,
    'package_size': packageSize,
    'sku': sku,
    'gtin': gtin,
    'catalog_product_id': catalogProductId,
    'confidence': confidence,
    'product_name_confidence': productNameConfidence,
    'brand_confidence': brandConfidence,
    'variant_confidence': variantConfidence,
    'sku_confidence': skuConfidence,
    'gtin_confidence': gtinConfidence,
    'evidence': evidence,
    'uncertainties': uncertainties,
  };

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
