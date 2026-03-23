#!/bin/bash
# Cognitive Stack — Quick Init Script

echo "🔧 Cognitive Stack Initialization"
echo "=================================="

WORKSPACE="/home/cmx/cmx-core"

# 1. Start Engram server
echo "📦 Starting Engram server..."
pkill -f "engram serve" 2>/dev/null
engram serve &
sleep 2

# 2. Navigate to workspace
echo "📁 Workspace: $WORKSPACE"
cd "$WORKSPACE" || exit 1

# 3. Check memory
echo "🧠 Memory check:"
engram stats 2>/dev/null | head -5

# 4. Search context
echo ""
echo "🔍 Searching for Cognitive Stack context..."
engram search "Cognitive Stack" 2>/dev/null || echo "No context found"

echo ""
echo "✅ Initialization complete!"
echo ""
echo "To start working:"
echo "  opencode                    # Open OpenCode"
echo "  gemini                      # Or Gemini CLI"
echo ""
echo "Then in the agent, run:"
echo "  /sdd-init                   # Initialize SDD"
