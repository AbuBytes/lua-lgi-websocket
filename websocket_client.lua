#!/usr/bin/env lua

local lgi = require('lgi')
local Gio = lgi.Gio
local GLib = lgi.GLib
local GObject = lgi.GObject

-- WebSocket connection details
local host = "localhost"
local port = 5010
local path = "/ws"

print("Attempting to connect to: ws://" .. host .. ":" .. port .. path)

-- Create socket connection
local client = Gio.SocketClient.new()
local main_loop = GLib.MainLoop.new()

-- Handle Ctrl+C gracefully
GLib.unix_signal_add(GLib.PRIORITY_HIGH, 2, function() -- SIGINT
    print("\n🛑 Interrupted by user")
    main_loop:quit()
    return false
end)

print("🔄 Starting WebSocket client...")
print("Press Ctrl+C to exit")

-- Connect to the server
client:connect_to_host_async(host, port, nil, function(client, result)
    local success, connection = pcall(function()
        return client:connect_to_host_finish(result)
    end)

    if not success or not connection then
        print("❌ Failed to connect to server: " .. tostring(connection))
        main_loop:quit()
        return
    end

    print("✓ TCP connection established")

    -- Get input and output streams
    local output_stream = connection:get_output_stream()
    local input_stream = connection:get_input_stream()

    -- Create WebSocket handshake request
    local handshake = "GET " .. path .. " HTTP/1.1\r\n" ..
        "Host: " .. host .. ":" .. port .. "\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ..
        "Sec-WebSocket-Version: 13\r\n" ..
        "\r\n"

    -- Send handshake
    local handshake_bytes = GLib.Bytes.new(handshake)
    output_stream:write_bytes_async(handshake_bytes, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
        local success, bytes_written = pcall(function()
            return stream:write_bytes_finish(result)
        end)

        if not success or bytes_written == 0 then
            print("❌ Failed to send handshake")
            main_loop:quit()
            return
        end

        print("📤 Handshake sent")

        -- Read handshake response
        input_stream:read_bytes_async(1024, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
            local success, response_bytes = pcall(function()
                return stream:read_bytes_finish(result)
            end)

            if not success or not response_bytes then
                print("❌ Failed to read handshake response")
                main_loop:quit()
                return
            end

            local response = response_bytes:get_data()
            print("📥 Handshake response received")

            if response:match("101 Switching Protocols") then
                print("✓ WebSocket connection established successfully!")

                -- Function to read WebSocket frames
                local function read_websocket_frame()
                    input_stream:read_bytes_async(2, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
                        local success, header_bytes = pcall(function()
                            return stream:read_bytes_finish(result)
                        end)

                        if not success or not header_bytes then
                            print("🔌 WebSocket connection closed")
                            main_loop:quit()
                            return
                        end

                        local header = header_bytes:get_data()
                        if #header < 2 then
                            print("🔌 WebSocket connection closed")
                            main_loop:quit()
                            return
                        end

                        local byte1 = header:byte(1)
                        local byte2 = header:byte(2)

                        local fin = (byte1 & 0x80) ~= 0
                        local opcode = byte1 & 0x0F
                        local masked = (byte2 & 0x80) ~= 0
                        local payload_len = byte2 & 0x7F

                        -- Read extended payload length if needed
                        local function read_payload(len)
                            if len == 0 then
                                -- Continue reading next frame
                                read_websocket_frame()
                                return
                            end

                            input_stream:read_bytes_async(len, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
                                local success, payload_bytes = pcall(function()
                                    return stream:read_bytes_finish(result)
                                end)

                                if success and payload_bytes then
                                    local payload = payload_bytes:get_data()
                                    if opcode == 1 then     -- Text frame
                                        print("📨 Received message: " .. payload)
                                    elseif opcode == 2 then -- Binary frame
                                        print("📨 Received binary message (length: " .. #payload .. ")")
                                    elseif opcode == 8 then -- Close frame
                                        print("🔌 WebSocket connection closed by server")
                                        main_loop:quit()
                                        return
                                    end
                                end

                                -- Continue reading next frame
                                read_websocket_frame()
                            end)
                        end

                        if payload_len < 126 then
                            read_payload(payload_len)
                        elseif payload_len == 126 then
                            -- Read 2-byte extended length
                            input_stream:read_bytes_async(2, GLib.PRIORITY_DEFAULT, nil, function(stream, result)
                                local success, len_bytes = pcall(function()
                                    return stream:read_bytes_finish(result)
                                end)

                                if success and len_bytes then
                                    local len_data = len_bytes:get_data()
                                    local actual_len = (len_data:byte(1) << 8) | len_data:byte(2)
                                    read_payload(actual_len)
                                else
                                    main_loop:quit()
                                end
                            end)
                        else
                            -- payload_len == 127, 8-byte extended length (not implemented for simplicity)
                            print("❌ Large frames not supported")
                            main_loop:quit()
                        end
                    end)
                end

                -- Start reading WebSocket frames
                read_websocket_frame()
            else
                print("❌ Failed to establish WebSocket connection")
                print("Response: " .. response)
                main_loop:quit()
            end
        end)
    end)
end)

-- Run the main loop
main_loop:run()

print("👋 WebSocket client terminated")
