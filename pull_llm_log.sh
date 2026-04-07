#!/bin/bash
# Pull LLM log from Android device to local machine

DEVICE_ID=$1
LOG_PATH="app_flutter/flutterclaw/logs/llm.log"
OUTPUT_PATH="/Users/dtroyal/flutterclaw/llm/log/llm.log"

if [ -z "$DEVICE_ID" ]; then
    echo "Usage: ./pull_llm_log.sh <device-id>"
    echo "Example: ./pull_llm_log.sh 25dc4e48400d7ece"
    exit 1
fi

echo "Pulling LLM log from device: $DEVICE_ID"

# Create output directory if not exists
mkdir -p /Users/dtroyal/flutterclaw/llm/log

# Use run-as to access app's private directory
adb -s $DEVICE_ID shell run-as ai.flutterclaw.flutterclaw cat "$LOG_PATH" > "$OUTPUT_PATH" 2>/dev/null

if [ $? -eq 0 ]; then
    if [ -s "$OUTPUT_PATH" ]; then
        echo "✓ Log pulled successfully to: $OUTPUT_PATH"
        echo ""
        echo "Last 30 lines of log:"
        tail -30 "$OUTPUT_PATH"
    else
        echo "✗ Log file is empty or doesn't exist yet"
        echo "Make sure the app has been run and LLM calls have been made"
    fi
else
    echo "✗ Failed to pull log"
    echo "Log file may not exist yet. Run the app and make LLM requests first."
fi