# AI Module: Overview & Architecture

StarterKit Foundation AI Module provides AI-powered content generation with Claude API integration.

## What is it?

The AI Module is a WordPress-integrated service that enables AI-powered content generation, optimization, and automation through a simple, extensible interface.

**Key Features:**
- 🤖 Claude API integration (primary)
- 🔌 Pluggable provider architecture (OpenAI-ready)
- ⚡ Response caching for cost reduction
- 🔒 Input validation & injection prevention
- 📊 Comprehensive logging & analytics
- 🌍 Environment-specific configuration
- ✅ Type-safe API with DTOs

## Why?

Modern WordPress projects need AI capabilities without reinventing the wheel. The AI Module provides:

- **Cost Control** - Smart caching reduces API calls
- **Reliability** - Fallback handling, retry logic
- **Security** - Validates all inputs, masks secrets
- **Flexibility** - Add new providers without changing code
- **Observability** - Full logging and monitoring
- **Standards** - Follows PSR-12, type-safe code

## How it works

### High-level flow

```
User/Plugin Request
     ↓
AIService (orchestration)
     ↓
Cache Layer? ──→ (hit) → Return cached response
     ↓ (miss)
PromptValidator (security check)
     ↓
Provider (Claude/OpenAI/Custom)
     ↓
API Call
     ↓
Response Processing
     ↓
Cache Storage
     ↓
Return AIResponse DTO
```

### Simple Example

```php
$ai = $container->get(\AIModule\Services\AIService::class);

$response = $ai->complete(
    new \AIModule\Models\CompletionRequest(
        userPrompt: 'Generate a blog title about WordPress performance',
        systemPrompt: 'You are an expert WordPress developer.',
        model: 'claude-3-5-sonnet-20241022'
    )
);

echo $response->text();  // "Top 10 WordPress Performance Optimization Tips in 2026"
```

## Architecture

### Core Components

#### 1. Providers
Pluggable AI service implementations.

- **ProviderInterface** - Contract that all providers must implement
- **AbstractProvider** - Common functionality (logging, error handling)
- **ClaudeProvider** - Claude API implementation
- **OpenAIProvider** - OpenAI implementation (extensible)

#### 2. Services
High-level operations.

- **AIService** - Main orchestration, caching, provider selection
- **CompletionService** - Text generation operations
- **ContentGenerationService** - WordPress content generation

#### 3. Models (DTOs)
Type-safe data transfer.

- **CompletionRequest** - Input specification
- **AIResponse** - Structured output
- **PromptTemplate** - Reusable prompt definitions

#### 4. Supporting Components
- **Cache** (AIResponseCache) - Response caching
- **Logger** (AILogger) - Operation logging
- **Security** (PromptValidator) - Input validation
- **Repository** (PromptTemplateRepository) - Template persistence

### Module Structure

```
kit-modules/ai-module/
├── src/
│   ├── App.php                    # Module bootstrap
│   ├── Providers/
│   │   ├── ProviderInterface.php  # Contract
│   │   ├── AbstractProvider.php   # Base class
│   │   ├── Claude/                # Claude implementation
│   │   └── OpenAI/                # OpenAI (extensible)
│   ├── Services/                  # Business logic
│   ├── Models/                    # DTOs
│   ├── Cache/                     # Caching
│   ├── Logger/                    # Logging
│   ├── Security/                  # Validation
│   └── Exception/                 # Custom exceptions
├── config/
│   ├── common/ai.php              # Base config
│   ├── production/ai.php          # Production overrides
│   ├── dev/ai.php                 # Dev overrides
│   └── local/ai.php               # Local overrides
└── tests/                         # Unit & integration tests
```

## Supported Providers

### Claude (Primary)

**Status**: ✅ Fully implemented

**Models:**
- `claude-3-5-sonnet-20241022` (balanced, recommended)
- `claude-3-5-haiku-20241022` (fast, cost-effective)
- `claude-opus-4-20250514` (powerful, slower)

**Features:**
- Streaming support
- Prompt caching for reduced costs
- Token usage tracking
- Error recovery with retries

**Configuration:**
```php
'providers' => [
    'claude' => [
        'api_key' => getenv('CLAUDE_API_KEY'),
        'models' => [
            'default' => 'claude-3-5-sonnet-20241022',
            'fast' => 'claude-3-5-haiku-20241022',
        ],
    ]
]
```

### OpenAI (Extensible)

**Status**: 🔄 Extensible skeleton (implement as needed)

**Models:**
- `gpt-4-turbo` (powerful)
- `gpt-3.5-turbo` (fast)

**To implement:**
```php
// Add anthropic-ai/sdk to composer.json requires
"openai/php-client": "^0.10"

// Implement in src/Providers/OpenAI/OpenAIProvider.php
class OpenAIProvider extends AbstractProvider { }

// Add to config/common/ai.php
'providers' => [
    'openai' => [
        'api_key' => getenv('OPENAI_API_KEY'),
    ]
]
```

## Configuration

### Per Environment

**local** (development):
```php
'cache' => ['enabled' => false],      // Fresh responses for testing
'logging' => ['level' => 'debug'],     // Verbose output
'rate_limit' => ['enabled' => false],  // No restrictions
```

**dev** (staging):
```php
'cache' => ['enabled' => false],       // Test fresh changes
'logging' => ['level' => 'debug'],     # See everything
'rate_limit' => ['enabled' => false],  # Testing
```

**stage** (staging verification):
```php
'cache' => ['enabled' => true],        # Enable for realism
'logging' => ['level' => 'info'],      # Normal logging
'rate_limit' => ['enabled' => true],   # Verify limits work
```

**prod** (production):
```php
'cache' => ['enabled' => true],        # Reduce costs
'logging' => ['level' => 'error'],     # Errors only
'rate_limit' => ['enabled' => true],   # Enforce quotas
```

### Environment Variables

```bash
# Required
CLAUDE_API_KEY=sk-ant-...              # Claude API key

# Optional
AI_PROVIDER=claude                     # Active provider (default: claude)
OPENAI_API_KEY=sk-...                 # OpenAI key (if using OpenAI)
ENVIRONMENT_TYPE=prod                 # Environment (local/dev/stage/prod)
```

## Quick Start

### 1. Setup

```bash
# Install Composer dependencies (including Anthropic SDK)
composer install

# Generate .env.secret from template
cp .env.secret.template .env.secret

# Add your Claude API key
echo 'CLAUDE_API_KEY=sk-ant-xxxx...' >> .env.secret
```

### 2. Use in Code

```php
// Get AI service from container
$ai = $container->get(\AIModule\Services\AIService::class);

// Create request
$request = new \AIModule\Models\CompletionRequest(
    userPrompt: 'Your prompt here',
    systemPrompt: 'Optional system context',
    model: 'claude-3-5-sonnet-20241022'
);

// Get response
$response = $ai->complete($request);

// Use the generated text
echo $response->text();
```

### 3. In WordPress Hooks

```php
add_action('wp_loaded', function() {
    global $container;
    $ai = $container->get(\AIModule\Services\AIService::class);
    
    // Generate content
    $title = $ai->complete(
        new \AIModule\Models\CompletionRequest(
            userPrompt: 'Generate a catchy post title'
        )
    )->text();
    
    // Save post
    wp_insert_post(['post_title' => $title]);
});
```

## Next Steps

- **For detailed API reference**: See [docs/AI_API.md](./AI_API.md)
- **For configuration guide**: See [docs/AI_CONFIGURATION.md](./AI_CONFIGURATION.md)
- **For security considerations**: See [docs/AI_SECURITY.md](./AI_SECURITY.md)
- **For integration patterns**: See [docs/AI_INTEGRATION.md](./AI_INTEGRATION.md)
- **For complete project reference**: See [docs/CLAUDE.md](./CLAUDE.md)

## Support

- 📚 **Full Documentation**: [docs/CLAUDE.md](./CLAUDE.md)
- 🐛 **Issues**: https://github.com/solidbunch/starter-kit-foundation/issues
- 💬 **Discussions**: https://github.com/solidbunch/starter-kit-foundation/discussions
