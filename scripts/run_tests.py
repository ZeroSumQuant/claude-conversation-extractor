#!/usr/bin/env python3
"""
Test runner with coverage reporting
"""

import subprocess
import sys


def main():
    """Run tests with coverage"""

    print("🧪 Running Claude Conversation Extractor Tests\n")

    # Test suites to run
    test_suites = [
        ("Core Extractor Tests", "tests/test_extractor.py"),
        ("Search Unit Tests", "tests/test_search.py"),
        ("Search Integration Tests", "tests/test_search_integration.py"),
        ("Interactive UI Tests", "tests/test_interactive_ui.py"),
        ("Real-time Search Unit Tests", "tests/test_realtime_search_unit.py"),
    ]

    # Run each test suite
    for name, test_file in test_suites:
        print(f"\n{'=' * 60}")
        print(f"Running: {name}")
        print(f"{'=' * 60}")

        cmd = [sys.executable, "-m", "pytest", test_file, "-v", "--tb=short"]

        result = subprocess.run(cmd)

        if result.returncode != 0:
            print(f"\n❌ {name} failed!")
        else:
            print(f"\n✅ {name} passed!")

    # Run coverage report
    print(f"\n{'=' * 60}")
    print("📊 Coverage Report")
    print(f"{'=' * 60}\n")

    coverage_cmd = [
        sys.executable,
        "-m",
        "pytest",
        "--cov=extract_claude_logs",
        "--cov=search_conversations",
        "--cov=interactive_ui",
        "--cov=realtime_search",
        "--cov-report=term-missing",
        "--cov-report=html",
        "-q",
    ]

    subprocess.run(coverage_cmd)

    print("\n📁 HTML coverage report saved to: htmlcov/index.html")
    print("\nTo view the report, run:")
    print("    open htmlcov/index.html  # macOS")
    print("    xdg-open htmlcov/index.html  # Linux")
    print("    start htmlcov/index.html  # Windows")


if __name__ == "__main__":
    main()
