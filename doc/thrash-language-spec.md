# Thrash Programming Language

> **Zig but it actually fucking works with optimizations**

## What is Thrash?

Thrash is a hard fork of Zig 0.14.1 that fixes critical optimization bugs and adds high-performance compilation features that Zig is too conservative to implement.

## Why Fork Zig?

Because waiting for upstream to fix critical bugs while our production code can't use optimizations is **unacceptable**. We need:

1. **Working optimizations** - No crashes with -O ReleaseFast on complex code
2. **Faster compilation** - Parallel compilation units, better caching
3. **Better performance** - More aggressive optimizations for HFT/quant systems
4. **No bullshit** - If it compiles in debug, it compiles in release

## Core Differences from Zig

### 1. Fixed Parameter Reference Optimization
- **Zig**: Crashes with large structs containing allocators
- **Thrash**: Smart PRO that actually works

### 2. Aggressive SIMD Optimization
- **Zig**: Conservative vectorization
- **Thrash**: Assumes modern CPUs, vectorizes aggressively

### 3. Compilation Speed
- **Zig**: Single-threaded in many passes
- **Thrash**: Parallel compilation, incremental builds that work

### 4. Optimization Levels
```bash
# Zig optimization levels
-O Debug
-O ReleaseSafe  
-O ReleaseSmall
-O ReleaseFast  # <- crashes on complex code

# Thrash optimization levels  
-O Debug
-O Safe         # ReleaseSafe equivalent
-O Small        # ReleaseSmall equivalent
-O Fast         # ReleaseFast that actually works
-O Thrash       # NEW: Maximum performance, no safety
-O Quant        # NEW: Optimized for HFT/quantitative systems
```

### 5. New Compiler Flags

```bash
# Thrash-specific flags
--parallel-compile     # Use all CPU cores
--force-inline-all     # Inline everything possible
--vectorize-aggressive # Maximum SIMD usage
--no-pro              # Disable Parameter Reference Optimization
--pro-threshold=N     # Set PRO threshold (default 64KB)
--cache-align         # Align all data for cache lines
--prefetch-hints      # Add CPU prefetch instructions
```

## Language Improvements

### 1. Better Comptime
```zig
// Thrash allows more complex comptime
comptime {
    // Can call external processes at compile time
    const data = @compileExec("./generate_tables.sh");
    
    // Can read files at compile time without @embedFile
    const config = @compileRead("config.json");
}
```

### 2. Force Optimization Attributes
```zig
// Force specific optimizations per function
pub fn hotPath() @optimize(.Thrash) void {
    // This function always uses maximum optimization
}

pub fn debugOnly() @optimize(.Debug) void {
    // This function never optimizes (for debugging)
}
```

### 3. SIMD Guarantees
```zig
// Thrash guarantees vectorization
pub fn searchBytes(haystack: []const u8, needle: u8) usize {
    @vectorize_or_error(32);  // Compile error if can't vectorize
    // ... search code ...
}
```

### 4. Cache Control
```zig
// Direct cache control
const CacheData = struct {
    data: [64]u8 @cache_align,        // Align to cache line
    hot: u32 @cache_hot,              // Keep in L1 cache
    cold: []u8 @cache_bypass,         // Skip cache
};
```

## Build System Improvements

### 1. Parallel Build by Default
```bash
thrash build-exe main.zig  # Uses all cores automatically
```

### 2. Incremental Compilation That Works
```bash
thrash build-exe main.zig --incremental  # Actually incremental
```

### 3. Profile-Guided Optimization
```bash
thrash build-exe main.zig --profile-generate
./main --benchmark
thrash build-exe main.zig --profile-use=profile.data
```

## Compatibility

- **99% Zig Compatible**: Most Zig code compiles unchanged
- **Thrash Extensions**: Optional, only if you use Thrash-specific features
- **Binary Compatible**: Can link with Zig-compiled libraries

## Performance Targets

For our Claude conversation extractor:
- **Zig Debug**: 169ms
- **Zig Release**: CRASHES
- **Thrash Fast**: 10-15ms (expected)
- **Thrash Thrash**: 5-8ms (maximum optimization)

## Implementation Plan

### Phase 1: Fix Critical Bugs (Week 1)
- [ ] Fix Parameter Reference Optimization
- [ ] Fix stack probe failures
- [ ] Fix LLVM optimization crashes

### Phase 2: Performance (Week 2)
- [ ] Add -O Thrash optimization level
- [ ] Implement aggressive vectorization
- [ ] Add cache control primitives

### Phase 3: Compilation Speed (Week 3)
- [ ] Parallel compilation passes
- [ ] Better incremental builds
- [ ] Compilation caching

### Phase 4: Language Features (Week 4)
- [ ] Enhanced comptime capabilities
- [ ] Optimization attributes
- [ ] SIMD guarantees

## Why "Thrash"?

Because we're thrashing the shit out of the CPU with optimizations that actually work. Also because Zig made us thrash around trying to get optimizations working.

## License

Same as Zig (MIT) but with "No Bullshit" clause: If it compiles in debug, it MUST compile in release.

## Motto

> "Zig's promise, Thrash's delivery"

## FAQ

**Q: Will Thrash be maintained long-term?**
A: Yes, because we need it for production HFT systems where performance matters.

**Q: Will you contribute fixes back to Zig?**
A: Yes, but we're not waiting for them to merge.

**Q: Is this a hostile fork?**
A: No, it's a "fuck it, we need this working NOW" fork.

**Q: Can I use Thrash in production?**
A: That's literally why we're making it.