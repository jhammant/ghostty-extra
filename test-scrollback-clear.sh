#!/bin/bash
# Test script for scrollback-clear-allowed config option
#
# This tests that when scrollback-clear-allowed = false,
# CSI 3 J (clear scrollback) is ignored.
#
# Usage: Run this inside Ghostty with the option set to false

echo "=== Scrollback Clear Test ==="
echo ""
echo "Step 1: Adding lines to scrollback..."
for i in {1..50}; do
    echo "Scrollback line $i - This should remain visible after test"
done

echo ""
echo "Step 2: Current position (you should see lines above)"
echo ""
echo "Step 3: Attempting to clear scrollback with CSI 3 J..."

# CSI 3 J - Erase scrollback buffer
printf '\033[3J'

echo ""
echo "Step 4: If scrollback-clear-allowed = false, scroll up should show lines 1-50"
echo "        If scrollback-clear-allowed = true (default), scrollback is gone"
echo ""
echo "=== Test Complete ==="
echo "Scroll up to verify scrollback was preserved (or not)"
