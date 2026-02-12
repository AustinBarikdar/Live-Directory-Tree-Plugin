#!/bin/bash
# Start the Live Directory Tree server

cd "$(dirname "$0")/server"
echo "Starting Live Directory Tree server..."
node server.js
