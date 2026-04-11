#!/bin/bash
# Simulates a ~20s build-like process with varied output lines

echo "==> Configuring project..."
sleep 1.2

echo "==> Resolving dependencies..."
sleep 0.8

echo "[1/8] Compiling utils.c"
sleep 2.0

echo "[2/8] Compiling parser.c"
sleep 3.1

echo "[3/8] Compiling lexer.c"
sleep 2.5

echo "[4/8] Compiling codegen.c"
sleep 1.8

echo "[5/8] Compiling optimizer.c"
sleep 2.4

echo "[6/8] Compiling runtime.c"
sleep 1.5

echo "[7/8] Compiling main.c"
sleep 1.0

echo "[8/8] Compiling tests.c"
sleep 0.9

echo "==> Linking binary..."
sleep 1.8

echo "==> Running 42 tests..."
sleep 1.2

echo "All tests passed."
echo "Build complete! ($(date +%s)s)"
