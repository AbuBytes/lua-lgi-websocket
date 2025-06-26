# Simple WebSocket Connector

A simple Lua script that connects to a WebSocket server using LGI (Lua GObject Introspection) bindings.

## Prerequisites

You need to have the following installed:

- Lua 5.1+
- LGI (Lua GObject Introspection)
- libsoup-3.0

### Installing dependencies on Ubuntu/Debian:

```bash
sudo apt install lua5.3 lua-lgi libsoup-3.0-dev
```

### Installing dependencies on Arch Linux:

```bash
sudo pacman -S lua lua-lgi libsoup3
```

## Usage

Run the WebSocket client:

```bash
./websocket_client.lua
```

Or:

```bash
lua websocket_client.lua
```

## Features

- ✅ Connects to `ws://localhost:5010/ws`
- ✅ Reports connection success or failure
- ✅ Prints all incoming text and binary messages
- ✅ Sends a test message upon connection
- ✅ Graceful handling of Ctrl+C interruption
- ✅ Automatic reconnection handling (connection close events)

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
