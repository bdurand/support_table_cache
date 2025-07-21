# Support Table Cache Architecture

This document describes the architecture and design of the `support_table_cache` gem, which provides automatic caching for ActiveRecord support table models.

## Overview

Support Table Cache is designed to optimize database queries for small lookup tables (support tables) that have:
- Unique keys (e.g., unique `name` attribute)
- Limited number of entries (a few hundred at most)
- Rarely updated data but frequently queried
- Used for data normalization (lookup tables)

The gem automatically caches records when using `find_by` methods and `belongs_to` associations, eliminating redundant database queries.

## High-Level Architecture

```mermaid
flowchart TB
    subgraph "Application Layer"
        App["Application Code"]
        Models["ActiveRecord Models"]
    end

    subgraph "Support Table Cache Gem"
        STC["SupportTableCache Module"]
        Assoc["Associations Module"]
        FindBy["FindByOverride"]
        RelOverride["RelationOverride"]
        MemCache["MemoryCache"]
    end

    subgraph "Cache Layer"
        RC["Rails.cache / Custom Cache"]
        MC["In-Memory Cache"]
    end

    subgraph "Database Layer"
        DB["PostgreSQL/MySQL/SQLite"]
    end

    App --> Models
    Models --> STC
    STC --> FindBy
    STC --> Assoc
    STC --> RelOverride
    STC --> MemCache

    FindBy --> RC
    FindBy --> MC
    Assoc --> RC
    Assoc --> MC
    RelOverride --> RC
    RelOverride --> MC

    FindBy -.-> DB
    Assoc -.-> DB
    RelOverride -.-> DB

    RC -.-> DB
    MC -.-> DB

    classDef appLayer fill:#e1f5fe
    classDef cacheLayer fill:#fff3e0
    classDef dbLayer fill:#f3e5f5
    classDef gemLayer fill:#e8f5e8

    class App,Models appLayer
    class STC,Assoc,FindBy,RelOverride,MemCache gemLayer
    class RC,MC cacheLayer
    class DB dbLayer
```

## Core Components

### 1. SupportTableCache Module

The main module that provides caching functionality to ActiveRecord models.

```mermaid
flowchart LR
    subgraph "SupportTableCache Module"
        CM["Class Methods"]
        IM["Instance Methods"]
        CC["Cache Configuration"]
        CCE["Cache Control & Expiry"]
    end

    subgraph "Class Methods"
        CB["cache_by()"]
        DC["disable_cache()"]
        EC["enable_cache()"]
        LC["load_cache()"]
        SC["support_table_cache="]
    end

    subgraph "Instance Methods"
        UC["uncache()"]
        ClearCache["support_table_clear_cache_entries()"]
    end

    CM --> CB
    CM --> DC
    CM --> EC
    CM --> LC
    CM --> SC

    IM --> UC
    IM --> ClearCache

    CB --> CC
    SC --> CC
    UC --> CCE
    ClearCache --> CCE
```

### 2. Cache Key Generation Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant Model as Model.find_by
    participant Override as FindByOverride
    participant Cache as Cache Store
    participant DB as Database

    App->>Model: Model.find_by(name: "example")
    Model->>Override: Intercept find_by call

    Override->>Override: Extract attributes from query
    Override->>Override: Check cache_by_attributes config
    Override->>Override: Generate cache key from attributes

    alt Cache Hit
        Override->>Cache: fetch(cache_key)
        Cache-->>Override: Return cached record
        Override-->>App: Return record
    else Cache Miss
        Override->>Cache: fetch(cache_key) with block
        Cache->>DB: Execute original find_by query
        DB-->>Cache: Return record from DB
        Cache->>Cache: Store record with TTL
        Cache-->>Override: Return record
        Override-->>App: Return record
    end
```

### 3. Cache Key Structure

```mermaid
flowchart TD
    Attrs["Query Attributes<br/>{name: 'active', type: 'primary'}"]

    subgraph "Key Generation Process"
        Sort["Sort attribute names<br/>['name', 'type']"]
        CaseCheck["Apply case sensitivity<br/>name: 'active' → 'active'<br/>type: 'primary' → 'primary'"]
        KeyGen["Generate cache key<br/>['ModelName', {name: 'active', type: 'primary'}]"]
    end

    Attrs --> Sort
    Sort --> CaseCheck
    CaseCheck --> KeyGen

    KeyGen --> CacheStore["Cache Store<br/>Key: ['Status', {name: 'active', type: 'primary'}]<br/>Value: #&lt;Status id: 1, name: 'active'&gt;"]
```

### 4. Association Caching Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant Parent as Parent Model
    participant Assoc as Association Reader
    participant Cache as Cache Store
    participant Child as Child Model
    participant DB as Database

    App->>Parent: parent.status
    Parent->>Assoc: Call association reader

    Assoc->>Assoc: Extract foreign key value
    Assoc->>Assoc: Build cache key from foreign key

    alt Cache Hit
        Assoc->>Cache: fetch(cache_key)
        Cache-->>Assoc: Return cached record
        Assoc-->>App: Return associated record
    else Cache Miss
        Assoc->>Cache: fetch(cache_key) with block
        Cache->>Child: Load association normally
        Child->>DB: Query database
        DB-->>Child: Return record
        Child-->>Cache: Return record
        Cache->>Cache: Store record with TTL
        Cache-->>Assoc: Return record
        Assoc-->>App: Return associated record
    end
```

### 5. Cache Invalidation Strategy

```mermaid
flowchart TD
    subgraph "Record Lifecycle Events"
        Create["Record Created"]
        Update["Record Updated"]
        Delete["Record Deleted"]
    end

    subgraph "Cache Invalidation Process"
        Hook["after_commit callback"]
        ExtractKeys["Extract all cacheable<br/>attribute combinations"]
        BuildKeys["Build cache keys for<br/>before & after states"]
        ClearCache["Delete cache entries"]
    end

    subgraph "Cache Keys Cleared"
        BeforeKeys["Keys with old values"]
        AfterKeys["Keys with new values"]
    end

    Create --> Hook
    Update --> Hook
    Delete --> Hook

    Hook --> ExtractKeys
    ExtractKeys --> BuildKeys
    BuildKeys --> ClearCache

    ClearCache --> BeforeKeys
    ClearCache --> AfterKeys
```

### 6. Cache Implementation Types

```mermaid
flowchart LR
    subgraph "Cache Types"
        subgraph "External Cache"
            RC["Rails.cache<br/>(Redis/Memcached)"]
            CC["Custom Cache Store"]
        end

        subgraph "In-Memory Cache"
            MC["MemoryCache<br/>(Process-local)"]
        end
    end

    subgraph "Configuration"
        Global["Global Cache<br/>SupportTableCache.cache = store"]
        PerClass["Per-Class Cache<br/>Model.support_table_cache = :memory"]
        Testing["Test Mode<br/>SupportTableCache.testing!"]
    end

    Global --> RC
    Global --> CC
    PerClass --> MC
    Testing --> MC

    subgraph "Trade-offs"
        ExtPros["✓ Shared across processes<br/>✓ Automatic invalidation<br/>✓ TTL support"]
        ExtCons["✗ Network overhead<br/>✗ Serialization cost"]

        MemPros["✓ Ultra-fast access<br/>✓ No network overhead<br/>✓ No serialization"]
        MemCons["✗ Per-process storage<br/>✗ Manual invalidation<br/>✗ Memory usage"]
    end

    RC -.-> ExtPros
    CC -.-> ExtPros
    RC -.-> ExtCons
    CC -.-> ExtCons

    MC -.-> MemPros
    MC -.-> MemCons
```

### 7. Testing Integration

```mermaid
flowchart TD
    subgraph "Test Execution"
        TestStart["Test Begins"]
        TestCode["Test Code Execution"]
        TestEnd["Test Ends"]
    end

    subgraph "Cache Isolation"
        TestCache["Isolated Test Cache<br/>(MemoryCache per test)"]
        CleanSlate["Clean State<br/>(No cache pollution)"]
    end

    TestStart --> TestCache
    TestCache --> TestCode
    TestCode --> CleanSlate
    CleanSlate --> TestEnd

    subgraph "Integration Pattern"
        RSpecWrap["RSpec around hook<br/>SupportTableCache.testing!"]
        MiniTestWrap["MiniTest around hook<br/>SupportTableCache.testing!"]
    end

    RSpecWrap -.-> TestCache
    MiniTestWrap -.-> TestCache
```

## Configuration Patterns

### Model Setup

```ruby
class Status < ApplicationRecord
  include SupportTableCache

  # Cache by single unique attribute
  cache_by :name, case_sensitive: false

  # Cache by composite unique key
  cache_by [:group, :name]

  # Cache by id (for associations)
  cache_by :id

  # Optional: Set TTL for cache entries
  self.support_table_cache_ttl = 5.minutes

  # Optional: Use in-memory cache
  self.support_table_cache = :memory
end
```

### Association Setup

```ruby
class Order < ApplicationRecord
  include SupportTableCache::Associations

  belongs_to :status
  cache_belongs_to :status
end
```

## Performance Benefits

### Query Elimination

```mermaid
sequenceDiagram
    participant App as Application
    participant Cache as Cache
    participant DB as Database

    Note over App,DB: Without Cache
    App->>DB: Status.find_by(name: 'active')
    DB-->>App: Record
    App->>DB: Status.find_by(name: 'active')
    DB-->>App: Same Record (redundant query)
    App->>DB: Status.find_by(name: 'active')
    DB-->>App: Same Record (redundant query)

    Note over App,DB: With Cache
    App->>Cache: Status.find_by(name: 'active')
    Cache->>DB: First query only
    DB-->>Cache: Record
    Cache-->>App: Record
    App->>Cache: Status.find_by(name: 'active')
    Cache-->>App: Record (from cache)
    App->>Cache: Status.find_by(name: 'active')
    Cache-->>App: Record (from cache)
```

## Design Principles

1. **Transparent Integration**: No code changes required beyond configuration
2. **Selective Caching**: Only caches queries that match configured unique keys
3. **Automatic Invalidation**: Cache entries are cleared when records change
4. **Flexible Cache Backends**: Supports various cache stores including in-memory
5. **Test Isolation**: Provides testing utilities to prevent cache pollution
6. **Performance Optimization**: Minimizes database queries for frequently accessed lookup data

## Use Cases

- **Status/Type Tables**: Small enums stored in database tables
- **Configuration Tables**: Application settings and parameters
- **Reference Data**: Countries, states, categories, etc.
- **Lookup Tables**: Any small, rarely-changing reference data

This architecture enables significant performance improvements for applications that heavily query small support tables while maintaining data consistency and providing flexible caching options.