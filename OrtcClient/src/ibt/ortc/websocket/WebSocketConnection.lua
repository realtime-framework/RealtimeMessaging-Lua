WebSocketConnection = {}
WebSocketConnection.__index = WebSocketConnection

local socket = require "socket"
local client

-- private
local function performHandshake (host, path)
	local result = false

  	client:send("GET "..path.." HTTP/1.1\r\n"
  		.. "User-Agent: Lua Web Socket Protocol Handshake\r\n"
	    .. "Upgrade: WebSocket\r\n"
	    .. "Connection: Upgrade\r\n"
	    .. "Host: "..host.."\r\n"
	    .. "Origin: http://"..host.."\r\n\r\n")

	local responsePart1 = client:receive();
	local responsePart2 = client:receive();
	local responsePart3 = client:receive();

	client:receive() --Websocket-Origin
	client:receive() --Websocket-Location
	client:receive() --null

	validHandshakeResponse = { "HTTP/1.1 101 Web Socket Protocol Handshake", "HTTP/1.1 101 WebSocket Protocol Handshake", "Upgrade: WebSocket", "Connection: Upgrade" }

	if (responsePart1 == validHandshakeResponse[1] or responsePart1 == validHandshakeResponse[2]) and responsePart2 == validHandshakeResponse[3] and responsePart3 == validHandshakeResponse[4] then
		result = true
	end

	return result
end

-- constructor
function WebSocketConnection:new (o)
	o = o or {} -- create object if user does not provide one
	setmetatable(o, self)
	self.__index = self
	return o
end

-- private
function receiveBlock (self, messageArrived)
	--print("WS RECEIVE BLOCK START")
	client:settimeout(0) -- do not block

	while true do
        local s, status, bytes = client:receive()

        --print(s)
        --print(status)

        if bytes and bytes ~= "" then
			--print("RECEIVED!")

			local receivedMessages = {}
			local plainTextMessage = ""
			local i = 1
			local j = 1
			local currByte = bytes:byte(i)

			while i <= string.len(bytes) do
				-- Last byte
				while currByte ~= 255 do
					-- First byte
					if currByte == 0 then
						plainTextMessage = ""
					else
						plainTextMessage = plainTextMessage..string.char(bytes:byte(i))
					end

					-- Next byte
					i = i + 1
					currByte = bytes:byte(i)
				end

				receivedMessages[j] = plainTextMessage
				j = j + 1

				-- Next byte
				i = i + 1
				currByte = bytes:byte(i)
			end

			if messageArrived ~= nil then
				messageArrived(self, receivedMessages)
			end

			--linda:send("x", receivedMessages) -- linda as upvalue
			--break
        end

        -- Check if the connection was closed
        if status == "closed" then
        	--print('CLOSED')

			messageArrived(self, { "disconnected;" })

        	--linda:send("x", { "disconnected;" }) -- linda as upvalue
        	break
        end
	end

	--print("WS RECEIVE BLOCK END")
end

-- public
function WebSocketConnection:connect (self, messageArrived, host, port, path)
	if port == nil then
		port = 80
	end

	client = socket.connect(host, port)

	if client ~= nil then
		local handshake = false

		if performHandshake(host, path) then
			handshake = true
		end

		messageArrived(self, { "handshake;"..(handshake and 1 or 0) })

		receiveBlock(self, messageArrived)

		--linda:send("x", { "handshake;"..(handshake and 1 or 0) }) -- linda as upvalue
	else
		messageArrived(self, { "reconnect;" })
	end
end

-- public
function WebSocketConnection:disconnect ()
	client:close()
end

-- public
function WebSocketConnection:send (msg)
	--print("Sending: "..msg)

	client:send("\000"..msg.."\255")
end
