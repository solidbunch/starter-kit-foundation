---
paths:
  - "web/wp-content/themes/starter-kit-theme/**/*.php"
  - "web/wp-content/plugins/starter-kit-addon/**/*.php"
---

# Carbon Fields

**Boot**: the THEME boots CF (`ThemeSettings::boot()` via `after_setup_theme` in theme `Hooks.php`).
The addon does NOT boot CF — never boot it twice.

**Register fields**: use the `carbon_fields_register_fields` hook — never `init` (silently fails):

```php
// In Hooks.php (theme or addon):
add_action('carbon_fields_register_fields', [Meta\PostMeta\MyType::class, 'make']);

// In src/Handlers/Meta/PostMeta/MyType.php:
public static function make(): void {
    $metaPrefix = SK_PREFIX . PostTypes\MyType::getKey() . '_';
    Container::make('post_meta', __('Settings', 'starter-kit'))
        ->where('post_type', '=', PostTypes\MyType::getKey())
        ->add_fields([ Field::make('text', $metaPrefix . 'field_name', __('Label', 'starter-kit')) ]);
}
```

One `Container::make` per CPT. Never call it before `carbon_fields_register_fields` fires.
Prefix pattern: `SK_PREFIX . PostTypes\Type::getKey() . '_'` for post meta; `SK_PREFIX` alone for
theme options.

**Read/write always via Utils** (see php.md):

```php
Utils::getPostMeta($postId, $metaPrefix . 'field_name');           // read
Utils::getPostMetaFw($postId, $metaPrefix . 'field_name');         // read complex / association
Utils::setPostMeta($postId, $metaPrefix . 'field_name', $value);   // write
```

## Field type gotchas — Claude gets these wrong without being told

- `checkbox` → returns `'yes'` / `''`, NOT `true` / `false`
- `relationship` is deprecated → use `association` instead
- `association` returns `[['id'=>..., 'type'=>..., 'subtype'=>...]]` → `wp_list_pluck($result, 'id')` for IDs
- `complex` (repeater) returns `array[]` → always null-check before iterating; read with `getPostMetaFw`
- `select` options format: `['value' => 'Label']`; dynamic: `->set_options(fn() => [...])`
- Container chain helpers: `->set_priority()`, `->set_context()`, `->set_width()`, `->set_conditional_logic()`
