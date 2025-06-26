#!/usr/bin/env lua

local WebSocket = require('lgi_websocket')

-- WebSocket connection URL
local url = "ws://localhost:5010/ws"

-- Create a new WebSocket client instance
-- with a custom retry interval of 3 seconds
local ws = WebSocket.new(url, { retry_interval = 3 })

-- 1. Fired when the connection is successfully opened
ws.onopen = function()
    print("✅ Connection opened!")
    -- Send a message to the server
    ws:send("Hello from the new WebSocket client!")
end

-- 2. Fired when a message is received from the server
ws.onmessage = function(message)
    print("📨 Received:", message)
end

-- 3. Fired when a connection error occurs
ws.onerror = function(err)
    print("❌ An error occurred:", tostring(err))
end

-- 4. Fired when the connection is closed
ws.onclose = function(was_clean, code, reason)
    print(string.format("🔌 Connection closed. Clean: %s, Code: %d, Reason: %s",
        tostring(was_clean), code, reason))
end

-- Start the client's main loop
ws:start()
