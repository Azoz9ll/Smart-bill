# SmartBill local API integration

The “منتجاتي” tab uses `StoreProductsSection`, `StoreProductsViewModel`, and `StoreProductsService`. The client currently expects a read-only `get_store_products.php` route returning `products`, `total`, `page`, and `per_page`, and supports search, store filtering, pagination, product images, current/original prices, and product detail links.

The Debug build reads `SMARTBILL_API_BASE_URL` from `Configuration/Debug-Info.plist` (or the process environment override); the current Cloudflare tunnel is configured there for simulator development only and is temporary. Set the Release build's `SMARTBILL_API_BASE_URL` user-defined setting to a stable verified HTTPS origin before release; it is inserted into the Release Info.plist at build time. Release requests require HTTPS; no HTTP or unrelated-host fallback is used. An optional path prefix is preserved when building the `get_store_products.php` route. `/sync_store_products.php` is the scraper's authenticated write endpoint and is not used by the app.

No provider API secrets belong in the app bundle. The legacy OpenAI/Vision key entries were removed from the Debug Info.plist; AI features that depended on those embedded keys need a server-side proxy or another secure credential flow before they can be used.

The API response contract is the existing Swift decoding model: `products`, `total`, `page`, and `per_page`, with each product containing `id`, `store_name`, `name`, `price`, `old_price`, `currency`, `product_url`, `image_url`, `size`, and `updated_at`. The user reports that this route returns this JSON when tested locally on the Oracle server; this workspace still has no server SSH access, so remote TLS, database-backed responses, and the field types remain unverified here. Do not publish a release until a verified HTTPS hostname is available and configured.

Receipt scanning, analysis, editing, history, statistics, login, and registration retain their existing implementation. Shared product models and network configuration remain unchanged. Monthly spending statistics are independent of the removed external pricing feature.

## Cleanup on 23 October 2026

Removed the obsolete external pricing HTTP handler, proxy library, associated Node tests, and deployment README. These were the only contents of the hidden backend handoff directory, which was also removed. Updated this document to remove obsolete feature references and earlier verification claims.

The Xcode project uses filesystem-synchronized groups. No explicit references to the removed files existed in project configuration or build phases, so no project-file edit was necessary.

No PHP endpoints, Python scraper files, MySQL tables, historical receipts, or user records were changed. Pre-existing workspace edits were preserved.

## Verification

The iPhone 17 Pro simulator application build succeeded. The existing suite completed with 5 tests passed and 3 failed (8 distinct tests; launch tests include repeated configurations). All three failures were connection failures to the unavailable local PHP server at `http://localhost:8000`: real catalog/images, catalog view model, and receipt history. Offline error handling and application launch tests passed.

Real supermarket product display and receipt history retrieval could not be confirmed without the PHP server. Camera capture, OCR, and a scan/save round trip were not exercised. No test expectations were weakened or replaced with fabricated data.

Build/test log: `/tmp/smartbill-removal-tests.log`.
Result bundle: `/tmp/smartbill-removal-build/Logs/Test/Run-Smart bill-2026.10.23_17-58-44-+0300.xcresult`.
