# AI Module: Complete API Reference

Complete API documentation for the AI Module.

## AIService

Main orchestration service for AI operations.

### complete()

```php
public function complete(
    CompletionRequest $request
): AIResponse
```

Generate completion from configured AI provider.

**Parameters:**
- `CompletionRequest $request` - Completion request with prompts and parameters

**Returns:** `AIResponse` - Generated response with metadata

**Throws:** `AIException` - If API call fails

**Example:**
```php
$response = $aiService->complete(
    new CompletionRequest(
        userPrompt: 'Write a short poem about PHP',
        systemPrompt: 'You are a poet.',
        model: 'claude-3-5-sonnet-20241022',
        maxTokens: 200,
        temperature: 0.8
    )
);

echo $response->text();
echo $response->tokensUsed;
echo $response->model;
```

## CompletionRequest (DTO)

Data transfer object for API requests.

### Constructor

```php
public function __construct(
    public string $userPrompt = '',
    public ?string $systemPrompt = null,
    public ?string $model = null,
    public int $maxTokens = 1024,
    public ?float $temperature = null,
    public bool $cacheControl = false,
    public array $metadata = [],
)
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `$userPrompt` | string | '' | The main prompt/question |
| `$systemPrompt` | string\|null | null | System instructions/context |
| `$model` | string\|null | null | Model to use (uses default if null) |
| `$maxTokens` | int | 1024 | Max output tokens |
| `$temperature` | float\|null | null | Creativity (0-1, null=default) |
| `$cacheControl` | bool | false | Enable prompt caching |
| `$metadata` | array | [] | Custom metadata |

### Static Methods

#### fromArray()

Create request from array (useful for REST endpoints):

```php
$request = CompletionRequest::fromArray([
    'user_prompt' => 'Generate a title',
    'system_prompt' => 'You are helpful',
    'model' => 'claude-3-5-sonnet-20241022',
    'max_tokens' => 500,
    'temperature' => 0.7,
]);
```

### Instance Methods

#### toArray()

Convert to array for logging:

```php
$array = $request->toArray();
// Returns:
// [
//     'user_prompt' => '...',
//     'system_prompt' => '...',
//     'model' => 'claude-3-5-sonnet-20241022',
//     'max_tokens' => 1024,
//     'temperature' => 0.7,
//     'cache_control' => false,
// ]
```

## AIResponse (DTO)

Data transfer object for API responses.

### Constructor

```php
public function __construct(
    public string $text = '',
    public string $model = '',
    public string $provider = '',
    public int $tokensUsed = 0,
    public array $metadata = [],
    public ?DateTime $createdAt = null,
)
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `$text` | string | Generated text response |
| `$model` | string | Model used for generation |
| `$provider` | string | Provider (claude, openai, etc.) |
| `$tokensUsed` | int | Total tokens consumed |
| `$metadata` | array | Provider-specific metadata |
| `$createdAt` | DateTime | Response timestamp |

### Methods

#### text()

Get response text:

```php
$text = $response->text();
// Same as: $response->text
```

#### toArray()

Convert to array for API responses:

```php
$array = $response->toArray();
// Returns:
// [
//     'text' => '...',
//     'model' => 'claude-3-5-sonnet-20241022',
//     'provider' => 'claude',
//     'tokens_used' => 157,
//     'created_at' => '2026-05-19T10:30:00+00:00',
//     'metadata' => [ ... ],
// ]
```

## ProviderInterface

Contract that all AI providers must implement.

### complete()

```php
public function complete(
    CompletionRequest $request
): AIResponse
```

Generate completion from provider.

**Implementations:**
- `ClaudeProvider` - Claude API
- `OpenAIProvider` - OpenAI API

### embed()

```php
public function embed(
    array $texts,
    string $model
): array
```

Generate embeddings (vector representations).

**Status**: Not yet implemented in any provider

**Parameters:**
- `$texts` - Array of strings to embed
- `$model` - Embedding model

**Returns:** Array of float arrays (vectors)

### validateConfig()

```php
public function validateConfig(): bool
```

Validate provider is properly configured.

**Returns:** true if valid

**Throws:** `AIException` if configuration invalid

### getName()

```php
public function getName(): string
```

Get provider identifier.

**Returns:** Provider name (e.g., 'claude', 'openai')

## ClaudeProvider

Claude API implementation.

### Features

- ✅ Text completion
- ✅ Streaming (setup not shown here)
- ✅ Prompt caching (via $cacheControl)
- ✅ Token tracking
- ✅ Error recovery with exponential backoff

### Models Available

```php
'models' => [
    'default' => 'claude-3-5-sonnet-20241022',
    'fast' => 'claude-3-5-haiku-20241022',
    'powerful' => 'claude-opus-4-20250514',
]
```

### Example with Prompt Caching

```php
$request = new CompletionRequest(
    systemPrompt: 'Complete project architecture documentation...',  // Cached
    userPrompt: 'How do I add a new feature?',
    model: 'claude-3-5-sonnet-20241022',
    cacheControl: true,  // Enable prompt caching
);

$response = $provider->complete($request);

// First call caches the system prompt
// Subsequent calls reuse cache (90% token savings)
```

## Exception Handling

### AIException

```php
namespace AIModule\Exception;

class AIException extends Exception {}
```

All AI operations throw `AIException` on failure.

**Example:**
```php
try {
    $response = $aiService->complete($request);
} catch (\AIModule\Exception\AIException $e) {
    // Handle error
    error_log('AI error: ' . $e->getMessage());
    
    // Return fallback
    return 'Unable to generate content at this time.';
}
```

## PromptValidator

Input validation and security.

### validate()

```php
public function validate(string $prompt): bool
```

Validate prompt for security issues.

**Parameters:**
- `$prompt` - Prompt text to validate

**Returns:** true if valid

**Throws:** `AIException` if validation fails

**Checks:**
- Length (max 10000 chars by default)
- Prompt injection patterns
- Malicious keywords

**Example:**
```php
$validator = new PromptValidator(['max_length' => 5000]);

try {
    $validator->validate($userInput);
    // Safe to use
} catch (\AIModule\Exception\AIException $e) {
    echo 'Invalid prompt: ' . $e->getMessage();
}
```

### sanitize()

```php
public function sanitize(string $prompt): string
```

Clean prompt of potentially dangerous content.

**Removes:**
- Null bytes
- Excessive whitespace
- Trim edges

**Example:**
```php
$clean = $validator->sanitize($userInput);
$response = $aiService->complete(
    new CompletionRequest(userPrompt: $clean)
);
```

## AIResponseCache

Response caching to reduce API calls.

### get()

```php
public function get(string $key): ?AIResponse
```

Retrieve cached response.

**Parameters:**
- `$key` - Cache key (e.g., 'ai_response_abc123')

**Returns:** `AIResponse` if cached, null otherwise

**Example:**
```php
$cached = $cache->get('ai_response_prompt_hash');
if ($cached) {
    return $cached;  // Return from cache
}

$response = $provider->complete($request);
```

### set()

```php
public function set(
    string $key,
    AIResponse $response,
    int $ttl = 3600
): void
```

Cache a response.

**Parameters:**
- `$key` - Cache key
- `$response` - Response to cache
- `$ttl` - Time-to-live in seconds

**Example:**
```php
$cache->set('ai_response_abc123', $response, 7200);
```

### clear()

```php
public function clear(string $pattern = 'ai_response_'): void
```

Clear cache entries matching pattern.

**Example:**
```php
// Clear all AI responses
$cache->clear('ai_response_');

// Clear specific prefix
$cache->clear('ai_response_product_');
```

## AILogger

Operation logging and analytics.

### log()

```php
public function log(
    $level,
    string $message,
    array $context = []
): void
```

Log message at specific level (PSR-3 compatible).

**Parameters:**
- `$level` - Log level (debug, info, warning, error)
- `$message` - Message with {placeholder} support
- `$context` - Data to interpolate

**Example:**
```php
$logger->log(LogLevel::INFO, 'Generated content', [
    'model' => 'claude-3-5-sonnet-20241022',
    'tokens_used' => 152,
    'post_id' => 123,
]);

// Logs: [2026-05-19 10:30:00] [info] Generated content with model=claude-... tokens_used=152 post_id=123
```

**Shortcuts:**
```php
$logger->debug($message, $context);
$logger->info($message, $context);
$logger->warning($message, $context);
$logger->error($message, $context);
```

### Features

- Masks sensitive data (API keys, etc.)
- Truncates long prompts
- Calculates token usage
- Stores in `/wp-content/logs/ai.log`

## PromptTemplateRepository

Manage reusable prompt templates.

### getTemplate()

```php
public function getTemplate(string $name): PromptTemplate
```

Get template by name.

**Example:**
```php
$template = $repository->getTemplate('product_description');
// Returns template with system_prompt, examples, etc.
```

### getAllTemplates()

```php
public function getAllTemplates(): array
```

Get all available templates.

**Returns:** Array of PromptTemplate objects

### saveTemplate()

```php
public function saveTemplate(PromptTemplate $template): int
```

Save template to database.

**Returns:** Post ID

## Usage Patterns

### Pattern 1: Simple Completion

```php
$ai = $container->get(\AIModule\Services\AIService::class);
$response = $ai->complete(
    new \AIModule\Models\CompletionRequest(
        userPrompt: 'Generate a title'
    )
);
echo $response->text();
```

### Pattern 2: With Error Handling

```php
try {
    $response = $aiService->complete($request);
} catch (\AIModule\Exception\AIException $e) {
    // Log error
    $logger->error('AI failed', ['error' => $e->getMessage()]);
    // Return fallback
    return 'Default title';
}
```

### Pattern 3: With Template

```php
$template = $repository->getTemplate('blog_title');
$response = $aiService->complete(
    new CompletionRequest(
        userPrompt: $topicInput,
        systemPrompt: $template->system_prompt
    )
);
```

### Pattern 4: Batch Processing

```php
foreach ($items as $item) {
    $request = new CompletionRequest(
        userPrompt: "Create title for: {$item->title}",
        model: 'claude-3-5-haiku-20241022'  // Use fast model for batch
    );
    
    $response = $aiService->complete($request);
    update_post_meta($item->id, '_ai_title', $response->text());
}
```

---

For complete project context, see [docs/CLAUDE.md](./CLAUDE.md).
