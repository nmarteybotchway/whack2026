import 'dart:convert';
import 'dart:typed_data';

import '../openrouter.dart';

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
  final int confidence;
  final int productNameConfidence;
  final int brandConfidence;
  final int variantConfidence;
  final int skuConfidence;
  final int gtinConfidence;
  final List<String> evidence;
  final List<String> uncertainties;

  String get displayName =>
      [?brand, ?productName, ?variant, ?packageSize].join(' ');

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

    int requiredConfidence(String key) {
      final value = json[key];
      if (value is! int || value < 0 || value > 100) {
        throw FormatException('$key must be an integer from 0 to 100');
      }
      return value;
    }

    List<String> stringList(String key) {
      final value = json[key];
      if (value is! List || value.any((entry) => entry is! String)) {
        throw FormatException('$key must be a list of strings');
      }
      return value.cast<String>();
    }

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
      confidence: requiredConfidence('confidence'),
      productNameConfidence: requiredConfidence('product_name_confidence'),
      brandConfidence: requiredConfidence('brand_confidence'),
      variantConfidence: requiredConfidence('variant_confidence'),
      skuConfidence: requiredConfidence('sku_confidence'),
      gtinConfidence: requiredConfidence('gtin_confidence'),
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

/// Identifies the exact packaged item visible in a camera photo.
class ProductIdentificationService {
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

  Future<ProductIdentification> identify(Uint8List jpegBytes) async {
    final response = await _openRouter.generate(
      prompt: _prompt,
      image: OpenRouterImage(jpegBytes),
      responseSchema: _responseSchema,
    );

    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Product identification was not a JSON object',
      );
    }
    final result = ProductIdentification.fromJson(decoded);

    // Do not present fabricated identifiers if a model violates the prompt.
    final gtin = result.gtin;
    if (gtin != null && !_isValidGtin(gtin)) {
      throw const FormatException('GTIN has an invalid length or check digit');
    }
    return result;
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

  void close() => _openRouter.close();
}
