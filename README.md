# Simple WebSocket Connector

A simple yet robust Lua WebSocket client using LGI (Lua GObject Introspection) bindings. This project provides a reusable, event-driven `WebSocket` class that is easy to integrate into other projects.

## Features

- **Event-Driven API**: Familiar `onopen`, `onmessage`, `onerror`, and `onclose` event handlers.
- **Automatic Reconnection**: Automatically attempts to reconnect if the connection is dropped, with a configurable retry interval.
- **Clean and Reusable**: Encapsulated in a `WebSocket` class for easy reuse.
- **LSP-Annotated**: Includes EmmyLua/LuaLS annotations for excellent editor support (autocompletion and type-checking).

## Prerequisites

You need to have the following installed:

- Lua 5.1+ (or LuaJIT)
- LGI (Lua GObject Introspection)
- GLib and Gio (usually come with a full GTK development environment)

#### Installing dependencies on Arch Linux:

```bash
sudo pacman -S lua lua-lgi
```

#### Installing dependencies on Ubuntu/Debian:

```bash
sudo apt install lua5.3 lua-lgi libgirepository1.0-dev
```

## Usage

The project is split into two main files:

1.  `lgi_websocket.lua`: A reusable library file containing the `WebSocket` class.
2.  `websocket_client.lua`: An example script showing how to use the class.

To run the example client:

```bash
./websocket_client.lua
```

### Using the `WebSocket` Class

Here is a quick guide on how to use the `WebSocket` class in your own project.

**1. Require the module:**

```lua
local WebSocket = require('lgi_websocket')
```

**2. Create a new client instance:**

You can specify a custom retry interval in the options table.

```lua
-- Connect to a WebSocket server
local url = "ws://localhost:5010/ws"

-- Create an instance with a custom retry interval of 3 seconds
local ws = WebSocket.new(url, { retry_interval = 3 })
```

**3. Assign event handlers:**

Implement the callback functions to handle different events.

```lua
-- Fired when the connection is successfully opened
ws.onopen = function()
    print("✅ Connection opened!")
    -- Now it's safe to send messages
    ws:send("Hello from the new WebSocket client!")
end

-- Fired when a message is received
ws.onmessage = function(message)
    print("📨 Received:", message)
end

-- Fired when an error occurs
ws.onerror = function(err)
    print("❌ An error occurred:", tostring(err))
end

-- Fired when the connection is closed
ws.onclose = function(was_clean, code, reason)
    print(string.format("🔌 Connection closed. Clean: %s, Code: %d, Reason: %s",
                        tostring(was_clean), code, reason))
end
```

**4. Start the client:**

This call will start the connection process and block until the connection is permanently closed (e.g., via `ws:close()` or Ctrl+C).

```lua
-- Start the client's main loop
ws:start()
```

### Public Methods

- `ws:send(data)`: Sends a string message to the server.
- `ws:close(code, reason)`: Closes the connection permanently and prevents reconnection.
- `ws:start()`: Starts the client and its event loop.

## Expected Output

```
Attempting to connect to: ws://localhost:5010/ws
🔄 Starting WebSocket client...
Press Ctrl+C to exit
✓ WebSocket connection established successfully!
📨 Received message: [incoming messages will appear here]
```

If connection fails:

```
Attempting to connect to: ws://localhost:5010/ws
🔄 Starting WebSocket client...
Press Ctrl+C to exit
❌ Failed to establish WebSocket connection
Status: 7 (Couldn't connect to server)
👋 WebSocket client terminated
```
