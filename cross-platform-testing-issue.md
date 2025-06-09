# Cross-Platform Testing Strategy for Real-Time Search

## Problem Description

The real-time search module (`realtime_search.py`) has platform-specific code for keyboard handling that needs proper testing across Windows, macOS, and Linux. Currently, our tests face challenges:

1. **Module Import Issues**: Windows-specific modules (like `msvcrt`) don't exist on macOS/Linux, causing test failures
2. **Platform Detection Timing**: Platform-specific imports happen at module load time, making mocking difficult
3. **Coverage Gaps**: Unable to properly test Windows code paths on macOS/Linux and vice versa

Current coverage is at 72%, with most missing coverage in platform-specific keyboard handling code.

## Proposed Solution

### Phase 1: Immediate Test Fixes
- Update `test_realtime_search_coverage.py` to properly mock platform modules before import
- Add platform-specific test decorators (`@skipIf`, `@skipUnless`)
- Ensure all tests pass on the development platform

### Phase 2: Code Refactoring for Testability
Create a more testable architecture:

```python
# platform_handlers.py
from abc import ABC, abstractmethod

class PlatformHandler(ABC):
    @abstractmethod
    def get_key(self, timeout: float) -> Optional[str]:
        pass
    
    @abstractmethod
    def clear_screen(self):
        pass

class WindowsHandler(PlatformHandler):
    def __init__(self):
        import msvcrt
        self.msvcrt = msvcrt
    # ... implementation

class UnixHandler(PlatformHandler):
    def __init__(self):
        import termios, tty, select
        self.termios = termios
        self.tty = tty
        self.select = select
    # ... implementation
```

### Phase 3: CI/CD Multi-Platform Testing
Implement GitHub Actions workflow:

```yaml
name: Cross-Platform Tests

on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        python-version: ['3.8', '3.9', '3.10', '3.11']
    
    runs-on: ${{ matrix.os }}
    
    steps:
    - uses: actions/checkout@v3
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt
        pip install -r requirements-dev.txt
    - name: Run tests
      run: |
        pytest tests/ -v --cov=realtime_search --cov-report=xml
    - name: Upload coverage
      uses: codecov/codecov-action@v3
```

### Phase 4: Platform-Specific Test Suites
- `tests/test_keyboard_windows.py` - Windows-only tests
- `tests/test_keyboard_unix.py` - Unix/Linux/macOS tests  
- `tests/test_keyboard_common.py` - Platform-agnostic logic tests

## Benefits

1. **Reliability**: Actual verification of platform-specific behavior
2. **Maintainability**: Clear separation of concerns
3. **Coverage**: Achieve true 100% coverage across all platforms
4. **User Experience**: Ensure smooth experience on all operating systems
5. **Future-Proof**: Easy to add new platforms or Python versions

## Alternative Approach

If refactoring is too extensive:
1. Use conditional test skipping based on `sys.platform`
2. Focus on testing business logic with comprehensive mocks
3. Rely on CI/CD for platform-specific validation
4. Document platform requirements clearly

## Acceptance Criteria

- [ ] All tests pass on Windows, macOS, and Linux
- [ ] Code coverage reaches 95%+ across all platforms
- [ ] CI/CD pipeline runs tests on all platforms
- [ ] Platform compatibility documented in README
- [ ] No platform-specific bugs reported by users

## Related Files

- `realtime_search.py` - Main module with platform-specific code
- `tests/test_realtime_search_*.py` - Current test files
- `.github/workflows/` - CI/CD configuration location

## Priority

High - This affects all users and is critical for production readiness

## Labels

- enhancement
- testing
- cross-platform
- documentation