import Foundation

/// USDA FoodData Central API key. Get a free key instantly at
/// https://fdc.nal.usda.gov/api-key-signup.html
///
/// This file is git-ignored so the key is not committed. When blank, the app
/// falls back to `NutritionEstimator`.
enum NutritionCredentials {
    static let usdaAPIKey = "OgtZH63a8Wnbmm3qNXtxzNxZbaWfvkf7kcKWdYSS"

    /// Spoonacular API key (free tier ~150 points/day). Used ONLY to seed the
    /// shared cloud catalog once — never per-user — to stay within the quota.
    static let spoonacularAPIKey = "3f0afcaa6653460294856f401f49fab4"
}
