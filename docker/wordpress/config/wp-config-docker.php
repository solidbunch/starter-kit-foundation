<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the installation.
 * You don't have to use the web site, you can copy this file to "wp-config.php"
 * and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * This has been slightly modified (to read environment variables) for use in Docker.
 *
 * @link    https://wordpress.org/support/article/editing-wp-config-php/
 *
 * @package WordPress
 */


/**
 * Copy of official WordPress wp-config-docker.php https://hub.docker.com/_/wordpress
 *
 * Added some constants and improvements with eval
 *
 */

// IMPORTANT: this file needs to stay in-sync with https://github.com/WordPress/WordPress/blob/master/wp-config-sample.php
// (it gets parsed by the upstream wizard in https://github.com/WordPress/WordPress/blob/f27cb65e1ef25d11b535695a660e7282b98eb742/wp-admin/setup-config.php#L356-L392)

// a helper function to lookup "env_FILE", "env", then fallback
if (!function_exists('getenv_docker')) {
    // https://github.com/docker-library/wordpress/issues/588 (WP-CLI will load this file 2x)
    function getenv_docker($env, $default)
    {
        if ($fileEnv = getenv($env . '_FILE')) {
            return rtrim(file_get_contents($fileEnv), "\r\n");
        } elseif (($val = getenv($env)) !== false) {
            return $val;
        } else {
            return $default;
        }
    }
}

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define('DB_NAME', getenv_docker('MYSQL_DATABASE', 'wordpress'));

/** MySQL database username */
define('DB_USER', getenv_docker('MYSQL_USER', 'example_username'));

/** MySQL database password */
define('DB_PASSWORD', getenv_docker('MYSQL_PASSWORD', 'example_password'));

/**
 * Docker image fallback values above are sourced from the official WordPress installation wizard:
 * https://github.com/WordPress/WordPress/blob/f9cc35ebad82753e9c86de322ea5c76a9001c7e2/wp-admin/setup-config.php#L216-L230
 * (However, using "example username" and "example password" in your database is strongly discouraged.  Please use strong, random credentials!)
 */

/** MySQL hostname */
define('DB_HOST', getenv_docker('MYSQL_HOST', 'database'));

/**
 * Database charset to use in creating database tables.
 * Using utf8mb4 store 4 byte characters
 * https://make.wordpress.org/core/2015/04/02/the-utf8mb4-upgrade/
 */
define('DB_CHARSET', getenv_docker('WP_DB_CHARSET', 'utf8mb4'));

/** The database collate type. Don't change this if in doubt. */
define('DB_COLLATE', getenv_docker('WP_DB_COLLATE', ''));

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY', getenv_docker('WP_AUTH_KEY', '33c8e3558915785bbe166b6e4af1b0a5a5d485d9'));
define('SECURE_AUTH_KEY', getenv_docker('WP_SECURE_AUTH_KEY', '6f0b7cb9b6e3249dd6e4d3581acdc9d4c52819f8'));
define('LOGGED_IN_KEY', getenv_docker('WP_LOGGED_IN_KEY', '242c58e13d1e49a82452d99a8bef4f64718e0a50'));
define('NONCE_KEY', getenv_docker('WP_NONCE_KEY', '10457e68a1e36f23897fc76583e109c5ba6f9df8'));
define('AUTH_SALT', getenv_docker('WP_AUTH_SALT', 'b09a766f816ddc5e5c9de9af89a0839342c2d575'));
define('SECURE_AUTH_SALT', getenv_docker('WP_SECURE_AUTH_SALT', '997f7653d978ed052e25bf31eec32f0bbbd323ff'));
define('LOGGED_IN_SALT', getenv_docker('WP_LOGGED_IN_SALT', 'b58a0c36279288cdde9705db1e8d873e358f4af2'));
define('NONCE_SALT', getenv_docker('WP_NONCE_SALT', 'dd1852c56db944d8c3465d0dea9e95e96a14a544'));
// (See also https://wordpress.stackexchange.com/a/152905/199287)

/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = getenv_docker('MYSQL_DB_PREFIX', 'wp_');

/**
 * Site main URL.
 *
 * Can be used with port http://example.com:8080
 *
 */
$app_protocol = getenv_docker('APP_PROTOCOL', '');

$app_domain = getenv_docker('APP_DOMAIN', '');

if ($app_protocol === 'https') {
    $app_port = getenv_docker('APP_HTTPS_PORT', '');
} else {
    $app_port = getenv_docker('APP_HTTP_PORT', '');
}

$app_url = $app_protocol . '://' . $app_domain;

if (!empty($app_port) && $app_port != 80 && $app_port != 443) {
    $app_url .= ':' . $app_port;
}

define('WP_SITEURL', $app_url);
define('WP_HOME', $app_url);

/**
 * Environment type
 *
 * local, development, staging, production
 * Use function wp_get_environment_type() to operate with it
 */
define('WP_ENVIRONMENT_TYPE', getenv_docker('WP_ENVIRONMENT_TYPE', 'production'));

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define('WP_DEBUG', !!getenv_docker('WP_DEBUG', ''));
define('WP_DEBUG_DISPLAY', !!getenv_docker('WP_DEBUG_DISPLAY', ''));
define('WP_DEBUG_LOG', getenv_docker('WP_DEBUG_LOG', ''));

/**
 * Additional log file for information messages
 */
define('APP_INFO_LOG', getenv_docker('APP_INFO_LOG', ''));

/**
 * The development mode configured on a site defines the kind of development work that the site is being used for.
 */
define('WP_DEVELOPMENT_MODE', getenv_docker('WP_DEVELOPMENT_MODE', ''));

/**
 * Memory limits
 *
 */
define('WP_MEMORY_LIMIT', getenv_docker('WP_MEMORY_LIMIT', '256M'));
define('WP_MAX_MEMORY_LIMIT', getenv_docker('WP_MAX_MEMORY_LIMIT', '512M'));

/**
 * Better to use server cron
 *
 * Look to ./config/crontabs snd ./logs/cron
 */
define('DISABLE_WP_CRON', !!getenv_docker('WP_DISABLE_WP_CRON', true));

/**
 * Some restrictions
 */
define('DISALLOW_FILE_EDIT', !!getenv_docker('DISALLOW_FILE_EDIT', true));
define('DISALLOW_FILE_MODS', !!getenv_docker('DISALLOW_FILE_MODS', true));
define('AUTOMATIC_UPDATER_DISABLED', !!getenv_docker('AUTOMATIC_UPDATER_DISABLED', true));

/**
 * Set the default theme to the built-in project-theme
 */
define('WP_DEFAULT_THEME', getenv_docker('WP_DEFAULT_THEME', 'twentytwentythree'));


/* Add any custom values between this line and the "stop editing" line. */

// If we're behind a proxy server and using HTTPS, we need to alert WordPress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
// (we include this by default because reverse proxying is extremely common in container environments)


/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
