# Receipt analysis endpoint deployment

`analyze_receipt.php` is a local deployment artifact. It has **not** been copied to Oracle Cloud. Install it as `/home/ubuntu/smartbill-api/analyze_receipt.php` only after reviewing the existing server authentication and web-server configuration.

## Request and response

The iOS app posts to `analyze_receipt.php` with `ServerSession.shared`, a single cookie-aware `URLSession` used by login, registration, and analysis:

```json
{"image_base64":"<raw base64-encoded JPEG bytes>"}
```

On success, the endpoint returns the extraction object directly:

```json
{
  "store":"",
  "currency":"SAR",
  "vat_amount":null,
  "invoice_total":null,
  "items":[
    {"name":"Product name","quantity":1,"size":"","price":2.5,"line_total":2.5,"category":"أطعمة"}
  ]
}
```

`price` is the unit price. Unknown numeric values are `null`; unreadable optional values do not invalidate other item rows. Errors use `{"error":{"code":"...","message":"..."}}` with a useful HTTP status. The endpoint only analyzes and returns data; it does not save receipts.

## Authentication requirement

The endpoint denies requests unless PHP session state contains a positive `$_SESSION['user_id']`. **The local project does not include `login.php`, `register.php`, or `db.php`, so I could not verify that login currently creates this session.** Returning `user_id` in JSON alone does not create a PHP session. Keep the current password verification exactly as it is. At the beginning of `login.php`, before output and before any `session_start()`, configure the session cookie and start the session:

```php
ini_set('session.use_only_cookies', '1');
ini_set('session.use_strict_mode', '1');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/',
    'secure' => true,      // the public app URL must be HTTPS
    'httponly' => true,
    'samesite' => 'Lax',
]);
session_start();
```

Inside the existing successful-password branch only, regenerate the session ID and set the ID from the already-verified database user record (not from request JSON), before emitting the current JSON response:

```php
session_regenerate_id(true);
$_SESSION['user_id'] = (int)$verifiedUser['id']; // use the existing verified user variable/column
```

Keep the existing response fields and password hash verification unchanged. `register.php` keeps its current behavior; registration alone must not set an authenticated user session unless the existing flow already logs the user in. iOS sends login and subsequent receipt analysis through the same `ServerSession.shared`; URLSession stores the `Set-Cookie` response and sends the matching cookie to the same HTTPS host and `/` path. A session expiry is returned by `analyze_receipt.php` as 401 and shown as a re-login message. No fixed API secret is placed in the app.

The endpoint applies a small per-session-user rate limit, an 8 MiB decoded JPEG cap, bounded JSON input, a 10-second connection timeout, and a 75-second OpenAI request timeout. It does not log image data, OpenAI credentials, upstream response bodies, or account details.

Use one HTTPS hostname for both login and analysis. Cookies are scoped to the hostname and `/`; changing a temporary Cloudflare Quick Tunnel hostname requires updating the Debug API URL and signing in again. Configure the PHP session save path writable by the PHP runtime user and set `session.gc_maxlifetime` to the intended idle timeout; PHP's default may be shorter than the app's expected login lifetime. Cloudflare and the origin web server must preserve `Set-Cookie` and `Cookie` headers.

## Install and protect server configuration

1. Confirm `db.php` loads `/home/ubuntu/smartbill-api/.env` into the PHP process environment and that cURL is enabled. The endpoint includes that file but does not alter it or the database.
2. Copy this file next to `db.php`. Do not replace existing PHP files.
3. Check the PHP-FPM/Apache runtime user and grant it read access to `.env` only. For a typical `www-data` group, use owner/group appropriate to the host and mode `0640`; use `0600` if the PHP process runs as the file owner. Do not make `.env` world-readable.
4. Keep `.env` outside the public document root if possible. Otherwise deny hidden files in the web-server configuration. For Apache, an appropriate rule is `<FilesMatch "^\.env(?:\..*)?$">Require all denied</FilesMatch>`; for Nginx, deny `location ~ /\.env`. Verify `/.env` returns 403 or 404 without showing its contents. Do not paste key values into shell output or logs.
5. Confirm successful login responds with a `Set-Cookie` header whose attributes include `Secure`, `HttpOnly`, `SameSite=Lax`, and `Path=/`. Do not print or share the cookie value. Confirm unauthenticated analysis returns 401, an expired session returns 401, and authenticated analysis returns only the extraction JSON. Use a disposable receipt image and do not save the returned products until reviewed. Test connection failure with the device offline and confirm it does not appear as an empty invoice.

The current workspace has no access to `/home/ubuntu/smartbill-api`, the server `.env`, or the current Cloudflare tunnel. Deployment, server authentication verification, `.env` HTTP exposure checks, and an actual OpenAI request remain outstanding.
