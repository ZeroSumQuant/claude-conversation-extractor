# Test Coverage Plan for Claude Conversation Extractor

## Current Coverage: 61%

## Goal: 100% Coverage with Robust, Non-Brittle Tests

### Test Strategy

1. **Avoid Brittle Tests**
   - Mock external dependencies (file system, terminal, time)
   - Use fixtures for consistent test data
   - Test behavior, not implementation details
   - Avoid hardcoded paths and values where possible

2. **Test Categories**
   - Unit tests: Test individual functions/methods
   - Integration tests: Test component interactions
   - Edge cases: Test error handling and boundary conditions

## Coverage Gaps and Test Plan

### 1. extract_claude_logs.py (44% coverage)
**Missing Coverage:**
- Command-line argument parsing
- File listing and display functions
- Markdown generation
- Export functionality

**Tests Needed:**
- [ ] Test command-line argument parsing (all flags)
- [ ] Test extract_conversation with various JSONL formats
- [ ] Test save_as_markdown with different conversation types
- [ ] Test error handling for missing/corrupt files
- [ ] Test batch operations (extract_all, extract_recent)
- [ ] Test output directory creation and permissions
- [ ] Test progress display functions

### 2. interactive_ui.py (82% coverage)
**Missing Coverage:**
- Folder selection dialog
- Error handling in menu selections
- File opening on different platforms

**Tests Needed:**
- [ ] Fix platform-specific tests (Windows startfile)
- [ ] Test folder selection with various inputs
- [ ] Test error handling for invalid selections
- [ ] Test keyboard interrupt handling
- [ ] Mock file system operations properly

### 3. realtime_search.py (61% coverage)
**Missing Coverage:**
- Platform-specific keyboard handling
- Terminal display functions
- Search worker thread
- Error handling

**Tests Needed:**
- [ ] Test Windows keyboard handler
- [ ] Test Unix keyboard handler with all special keys
- [ ] Test terminal display methods
- [ ] Test search worker thread behavior
- [ ] Test debouncing logic
- [ ] Test cache management
- [ ] Test error recovery

### 4. search_conversations.py (61% coverage)
**Missing Coverage:**
- Semantic search (spaCy integration)
- Various helper methods
- Error handling paths

**Tests Needed:**
- [ ] Test with/without spaCy installed
- [ ] Test all search modes thoroughly
- [ ] Test date filtering edge cases
- [ ] Test content extraction from various formats
- [ ] Test relevance calculation
- [ ] Test context extraction
- [ ] Test error handling for corrupt JSONL

## Implementation Plan

### Phase 1: Fix Existing Failing Tests (Priority: HIGH)
1. Fix date filter test - use consistent timestamps
2. Fix exact match test - handle case sensitivity properly
3. Fix Windows-specific test mocking
4. Fix integration tests with proper mocks

### Phase 2: Core Functionality Tests (Priority: HIGH)
1. Complete extract_claude_logs.py tests
2. Add missing search_conversations.py tests
3. Ensure all error paths are tested

### Phase 3: UI and Platform Tests (Priority: MEDIUM)
1. Complete interactive_ui.py tests
2. Complete realtime_search.py tests
3. Add cross-platform compatibility tests

### Phase 4: Edge Cases and Error Handling (Priority: MEDIUM)
1. Test all error conditions
2. Test boundary conditions
3. Test resource cleanup

## Test Best Practices

1. **Use Fixtures**
   ```python
   @pytest.fixture
   def sample_conversation():
       return [...]
   ```

2. **Mock External Dependencies**
   ```python
   @patch('pathlib.Path.exists')
   @patch('builtins.open')
   ```

3. **Test Data Isolation**
   - Use tempfile for test files
   - Clean up after tests
   - Don't depend on external state

4. **Parameterized Tests**
   ```python
   @pytest.mark.parametrize("input,expected", [...])
   ```

5. **Clear Test Names**
   - test_should_X_when_Y
   - test_handles_X_error
   - test_returns_X_for_Y_input

## Success Metrics

- [ ] 100% code coverage
- [ ] All tests pass consistently
- [ ] Tests run in < 10 seconds
- [ ] No flaky tests
- [ ] Clear error messages on failure
- [ ] Tests document behavior