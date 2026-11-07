// Template for lib/secrets.dart, which is git-ignored and holds real keys.
//
// Set up once per checkout:
//   cp lib/secrets.example.dart lib/secrets.dart
// then paste your keys into lib/secrets.dart. Never commit that file.

/// OpenRouter API key, from https://openrouter.ai/keys.
const openRouterApiKey = '';

/// Veryfi receipt-API credentials, from https://app.veryfi.com (Settings ->
/// API Keys). Create a client, then copy the client id, username, and key.
const veryfiClientId = '';
const veryfiUsername = '';
const veryfiApiKey = '';

/// FoodBase API key, from the FoodBase dashboard.
const foodBaseApiKey = '';

/// USDA FoodData Central API key, from https://fdc.nal.usda.gov/api-key-signup/.
const usdaApiKey = '';
