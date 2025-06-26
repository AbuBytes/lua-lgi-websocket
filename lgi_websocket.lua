-- lgi_websocket.lua

local lgi = require('lgi')
local Gio = lgi.Gio
local GLib = lgi.GLib
-- local GObject = lgi.GObject -- Unused

---@meta

--- A robust, event-driven WebSocket client class using LGI bindings.
---
--- Provides an API similar to the browser's WebSocket object, with
--- automatic reconnection capabilities.
---@class WebSocket
---@field url string The WebSocket URL.
---@field host string The server host.
---@field port number The server port.
---@field path string The request path.
---@field options table The options table provided on creation.
---@field retry_interval number The interval in seconds to wait before reconnecting.
---@field onopen fun() Callback fired when the connection is successfully established.
---@field onmessage fun(message: string) Callback fired when a message is received.
---@field onerror fun(err: string) Callback fired when a connection error occurs.
---@field onclose fun(was_clean: boolean, code: number, reason: string) Callback fired when the connection is closed.
---@field send fun(self: WebSocket, data: string)
---@field close fun(self: WebSocket, code?: number, reason?: string)
---@field start fun(self: WebSocket)
---@field private _connection any The underlying Gio.SocketConnection.
---@field private _is_connected boolean True if the websocket is currently connected.
---@field private _should_reconnect boolean True if the client should attempt to reconnect on close.
---@field private _reconnect_timer number|nil The ID of the reconnection timer source.
---@class (internal) WebSocketInternal: WebSocket
---@field client any The underlying Gio.SocketClient.
---@field _main_loop any The GLib.MainLoop instance.
local WebSocket = {}
WebSocket.__index = WebSocket

---@class WebSocketOptions
---@field retry_interval? number The interval in seconds to wait before attempting to reconnect (default: 5).

--- Creates a new WebSocket client instance.
---@param url string The WebSocket URL (e.g., "ws://localhost:5010/ws").
---@param options? WebSocketOptions An optional table of settings.
---@return WebSocket
function WebSocket.new(url, options)
    ---@type WebSocketInternal
    local self = setmetatable({}, WebSocket)

    local success, parsed_uri = pcall(GLib.Uri.parse, url, GLib.UriFlags.NONE)
    if not success or not parsed_uri then
        error("Invalid WebSocket URL: " .. url)
    end

    self.url = url
    self.host = parsed_uri:get_host()
    self.port = parsed_uri:get_port()
    if self.port == -1 then self.port = (parsed_uri:get_scheme() == "wss") and 443 or 80 end
    self.path = parsed_uri:get_path() or "/"

    self.options = options or {}
    self.retry_interval = self.options.retry_interval or 5 -- in seconds

    -- Event handlers
    self.onopen = function() end
    self.onmessage = function(message) end
    self.onerror = function(err) end
    self.onclose = function(was_clean, code, reason) end

    self.client = Gio.SocketClient.new()
    self._main_loop = GLib.MainLoop.new()
    self._connection = nil
    self._is_connected = false
    self._should_reconnect = true
    self._reconnect_timer = nil

    return self
end

--- Internal method to initiate the connection.
---@private
function WebSocket:_connect()
    print("Attempting to connect to: " .. self.url)
    self.client:connect_to_host_async(self.host, self.port, nil, function(client, result)
        local success, connection = pcall(function()
            return client:connect_to_host_finish(result)
        end)

        if not success or not connection then
            self:_handle_error("Failed to connect to host: " .. tostring(connection))
            self:_schedule_reconnect()
            return
        end

        self._connection = connection
        self:_do_handshake()
    end)
end

--- Internal method to perform the WebSocket handshake.
---@private
function WebSocket:_do_handshake()
    local output_stream = self._connection:get_output_stream()
    local input_stream = self._connection:get_input_stream()

    local handshake = "GET " .. self.path .. " HTTP/1.1\r\n" ..
        "Host: " .. self.host .. ":" .. self.port .. "\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ..
        "Sec-WebSocket-Version: 13\r\n" ..
        "\r\n"

    local handshake_bytes = GLib.Bytes.new(handshake)
    output_stream:write_bytes_async(handshake_bytes, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
        local success, bytes_written = pcall(function()
            return stream:write_bytes_finish(result)
        end)

        if not success or bytes_written == 0 then
            self:_handle_error("Failed to send handshake")
            self:_schedule_reconnect()
            return
        end

        input_stream:read_bytes_async(1024, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
            local success, response_bytes = pcall(function()
                return stream:read_bytes_finish(result)
            end)

            if not success or not response_bytes then
                self:_handle_error("Failed to read handshake response")
                self:_schedule_reconnect()
                return
            end

            local response = response_bytes:get_data()
            if response:match("101 Switching Protocols") then
                self._is_connected = true
                self:onopen()
                self:_read_frames()
            else
                self:_handle_error("Handshake failed: " .. response)
                self:_schedule_reconnect()
            end
        end)
    end)
end

--- Internal method to continuously read WebSocket frames.
---@private
function WebSocket:_read_frames()
    local input_stream = self._connection:get_input_stream()

    input_stream:read_bytes_async(2, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
        local success, header_bytes = pcall(function() return stream:read_bytes_finish(result) end)
        if not success or not header_bytes or header_bytes:get_size() < 2 then
            self:_handle_close(false, 1006, "Abnormal closure")
            return
        end

        local header = header_bytes:get_data()
        local byte1, byte2 = header:byte(1), header:byte(2)
        -- local fin = (byte1 & 0x80) ~= 0 -- Unused
        local opcode = byte1 & 0x0F
        local payload_len = byte2 & 0x7F

        local function read_payload(len)
            if len == 0 then
                self:_read_frames()
                return
            end

            input_stream:read_bytes_async(len, GLib.PRIORITY_DEFAULT, nil, function(stream, res)
                local ok, payload_bytes = pcall(function() return stream:read_bytes_finish(res) end)
                if ok and payload_bytes then
                    local payload = payload_bytes:get_data()
                    if opcode == 1 then     -- Text
                        self.onmessage(payload)
                    elseif opcode == 8 then -- Close
                        self:_handle_close(true, 1000, "Normal closure")
                        return
                    end
                    self:_read_frames()
                else
                    self:_handle_close(false, 1006, "Abnormal closure")
                end
            end)
        end

        if payload_len < 126 then
            read_payload(payload_len)
        elseif payload_len == 126 then
            input_stream:read_bytes_async(2, GLib.PRIORITY_DEFAULT, nil, function(stream, res)
                local ok, len_bytes = pcall(function() return stream:read_bytes_finish(res) end)
                if ok and len_bytes then
                    local d = len_bytes:get_data()
                    read_payload((d:byte(1) << 8) | d:byte(2))
                else
                    self:_handle_close(false, 1006, "Abnormal closure")
                end
            end)
        else
            self:_handle_close(false, 1011, "Large frames not supported")
        end
    end)
end

--- Internal error handler.
---@param err string The error message.
---@private
function WebSocket:_handle_error(err)
    if self._is_connected then
        -- This will trigger the onclose event and schedule reconnection
        self:_handle_close(false, 1011, err)
    end
    self.onerror(err)
end

--- Internal close handler.
---@param was_clean boolean True if the connection closed cleanly.
---@param code number The WebSocket closing status code.
---@param reason string A description of why the connection closed.
---@private
function WebSocket:_handle_close(was_clean, code, reason)
    if self._connection then
        self._connection:close(nil)
        self._connection = nil
    end

    local was_connected = self._is_connected
    self._is_connected = false

    if was_connected then
        self.onclose(was_clean, code, reason)
    end

    self:_schedule_reconnect()
end

--- Internal method to schedule a reconnection attempt.
---@private
function WebSocket:_schedule_reconnect()
    if not self._should_reconnect then return end

    if self._reconnect_timer then GLib.Source.remove(self._reconnect_timer) end

    print(string.format("Reconnecting in %d seconds...", self.retry_interval))
    self._reconnect_timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, self.retry_interval, function()
        self:_connect()
        self._reconnect_timer = nil
        return false -- run only once
    end)
end

--- Sends a text message to the WebSocket server.
---@param data string The message to send.
function WebSocket:send(data)
    if not self._is_connected then
        self:_handle_error("Cannot send data: not connected")
        return
    end

    local output_stream = self._connection:get_output_stream()
    local payload_len = #data
    local header

    if payload_len < 126 then
        header = string.char(0x81, payload_len)
    elseif payload_len <= 0xFFFF then
        header = string.char(0x81, 126, payload_len >> 8, payload_len & 0xFF)
    else
        -- 8-byte length not implemented for simplicity
        self:_handle_error("Cannot send data: payload too large")
        return
    end

    local frame = GLib.Bytes.new(header .. data)
    output_stream:write_bytes_async(frame, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
        local ok, bytes_written = pcall(function() return stream:write_bytes_finish(result) end)
        if not ok then
            self:_handle_error("Failed to send data: " .. tostring(bytes_written))
        end
    end)
end

--- Closes the WebSocket connection permanently.
---
--- This will prevent any further reconnection attempts.
---@param code? number The WebSocket closing status code (default: 1000).
---@param reason? string A description for closing (default: "Normal closure").
function WebSocket:close(code, reason)
    self._should_reconnect = false
    if self._reconnect_timer then
        GLib.Source.remove(self._reconnect_timer)
        self._reconnect_timer = nil
    end

    if self._is_connected then
        -- Send a close frame
        local code_to_send = code or 1000
        local reason_to_send = reason or ""
        local frame_data = string.pack(">H", code_to_send) .. reason_to_send
        local header = string.char(0x88, #frame_data)
        local frame = GLib.Bytes.new(header .. frame_data)

        local stream = self._connection:get_output_stream()
        stream:write_bytes_async(frame, GLib.PRIORITY_DEFAULT, nil, function()
            self:_handle_close(true, code_to_send, reason_to_send)
        end)
    else
        self:_handle_close(true, code or 1000, reason or "Normal closure")
    end

    if self._main_loop:is_running() then
        self._main_loop:quit()
    end
end

--- Starts the client, initiates the connection, and runs the GLib Main Loop.
---
--- This function will block until `main_loop:quit()` is called (e.g., by `ws:close()` or Ctrl+C).
function WebSocket:start()
    GLib.unix_signal_add(GLib.PRIORITY_HIGH, 2, function() -- SIGINT
        print("\n🛑 Interrupted by user")
        self:close(1000, "User interrupted")
        return false
    end)

    self:_connect()
    self._main_loop:run()
    print("👋 WebSocket client terminated")
end

return WebSocket
