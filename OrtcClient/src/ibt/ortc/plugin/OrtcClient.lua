-- Comment these requires when generating unique file with squish
-- http://matthewwild.co.uk/projects/squish
package.path = package.path..";../OrtcClient/src/ibt/ortc/extensibility/?.lua;../OrtcClient/src/ibt/ortc/websocket/?.lua"
require("ProxyProperties")
require("Strings")
require("WebSocketConnection")
require("lfs")
local URI = nil
URI = require ("uri")

OrtcClient = {}
OrtcClient.__index = OrtcClient

local http = require "socket.http"
--local linda = lanes.linda()

local OPERATION_PATTERN = "^a%[\"{\\\"op\\\":\\\"(.-[^\\\"]+)\\\",(.*)}\"%]$"
local CLOSE_PATTERN = "^c%[(.*[^\"]+),\"(.*)\"%]$"
local VALIDATED_PATTERN = "^\\\"up\\\":(.*),\\\"set\\\":(.*)$"
local CHANNEL_PATTERN = "^\\\"ch\\\":\\\"(.*)\\\"$"
local EXCEPTION_PATTERN_1 = "^\\\"ex\\\":{\\\"op\\\":\\\"(.*[^\"]+)\\\",\\\"ex\\\":\\\"(.*)\\\"}$"
local EXCEPTION_PATTERN_2 = "^\\\"ex\\\":{\\\"op\\\":\\\"(.*[^\"]+)\\\",\\\"ch\\\":\\\"(.*)\\\",\\\"ex\\\":\\\"(.*)\\\"}$"
local RECEIVED_PATTERN = "^a%[\"{\\\"ch\\\":\\\"(.*)\\\",\\\"m\\\":\\\"([%s%S]*)\\\"}\"%]$"
local MULTI_PART_MESSAGE_PATTERN = "^(.[^_]*)_(.[^-]*)-(.[^_]*)_([%s%S]*)$"
local PERMISSIONS_PATTERN = "\\\"(.[^\\\"]+)\\\":\\\"(.[^,\\\"]+)\\\",?"
local CLUSTER_RESPONSE_PATTERN = "var SOCKET_SERVER = \"(.*)\";"

local MAX_MESSAGE_SIZE = 800
local MAX_CHANNEL_SIZE = 100
local MAX_CONNECTION_METADATA_SIZE = 256
local SESSION_STORAGE_NAME = "ortcsession-"

local conn = nil
local isCluster = nil
local subscribedChannels = nil
local messagesBuffer = nil
local permissions = nil
local isConnecting = nil
local isReconnecting = nil
local isValid = nil
local stopReconnecting = nil
local sessionExpirationTime = nil

-- private
local attributeSetters = {
  url = function(self, url)
  	isCluster = false
    local priv = getmetatable(self).priv
    priv.url = Strings:trim(url)
  end,

  clusterUrl = function(self, clusterUrl)
  	isCluster = true
    local priv = getmetatable(self).priv
    priv.clusterUrl = Strings:trim(clusterUrl)
  end
}

-- private: Calls the onConnected callback if defined.
local function delegateConnectedCallback (ortc)
    if ortc and ortc.onConnected then
        ortc.onConnected(ortc)
    end
end

-- private: Calls the onDisconnected callback if defined.
local function delegateDisconnectedCallback (ortc)
    if ortc and ortc.onDisconnected then
        ortc.onDisconnected(ortc)
    end
end

-- private: Calls the onSubscribed callback if defined.
local function delegateSubscribedCallback (ortc, channel)
    if ortc and ortc.onSubscribed and channel then
        ortc.onSubscribed(ortc, channel)
    end
end

-- private: Calls the onUnsubscribed callback if defined.
local function delegateUnsubscribedCallback (ortc, channel)
    if ortc and ortc.onUnsubscribed and channel then
        ortc.onUnsubscribed(ortc, channel)
    end
end

-- private: Calls the onMessages callbacks if defined.
local function delegateMessagesCallback (ortc, channel, message)
    if ortc and subscribedChannels[channel] and subscribedChannels[channel].isSubscribed and subscribedChannels[channel].onMessageCallback then
        subscribedChannels[channel].onMessageCallback(ortc, channel, message)
    end
end

-- private: Calls the onException callback if defined.
local function delegateExceptionCallback (ortc, event)
    if ortc and ortc.onException then
        ortc.onException(ortc, event)
    end
end

-- private: Calls the onReconnecting callback if defined.
local function delegateReconnectingCallback (ortc)
    if ortc and ortc.onReconnecting then
        ortc.onReconnecting(ortc)
    end
end

-- private: Calls the onReconnected callback if defined.
local function delegateReconnectedCallback (ortc)
    if ortc and ortc.onReconnected then
        ortc.onReconnected(ortc)
    end
end

-- private
local function getClusterServer (clusterUrl)
	local response = http.request(clusterUrl)
	local url = nil

	if response ~= nil then
		_, _, url = string.find(response, CLUSTER_RESPONSE_PATTERN)
	end

	return url
end

--private
local function doReconnect (self)
	self.isConnected = false

	if not stopReconnecting then
		isReconnecting = true

		delegateReconnectingCallback(self)

		self:doConnect()
	end
end

-- private
local function doStopReconnecting ()
	isConnecting = false

	-- Stop the connecting/reconnecting process
	stopReconnecting = true
end


-- private
local function messageArrived (self, x)
	if type(x) == "table" then
		for k = 1, table.getn(x) do
			local message = x[k]

			--print(message)

			if message ~= "o" and message ~= "h" then
				message = string.gsub(message, "\\\\\\\\", "\\")

				local _, _, op, args = string.find(message, "^(.*[^;]+);(.*)$")

				--if op == nil then
					--print("timed out")

				if op ~= nil then
					if op == "handshake" then
						if args == "1" then
							local status, err = pcall(function ()
								if unexpected_condition then
									error()
								end
								self.sessionId = Strings:generateId(16)
								conn:send("\"validate;"..self.appKey..";"..self.authToken..";"..(self.announcementSubChannel or "")..";"..(self.sessionId or "")..";"..(self.connectionMetadata or "").."\"")
							end)

							if err ~= nil then
								delegateExceptionCallback(self, err)

								doStopReconnecting()

								conn:disconnect()
							end
						else
							delegateExceptionCallback(self, "Unable to perform handshake")
						end
					elseif op == "disconnected" then
						-- Clear user permissions
						permissions = {}

						isConnecting = false
						isReconnecting = false

						if isValid then
							delegateDisconnectedCallback(self)

							if self.isConnected then
								doReconnect(self)
							end
						end

						self.isConnected = false
					elseif op == "reconnect" then
						isConnecting = false

						delegateExceptionCallback(self, "Unable to connect")

						socket.sleep(self.connectionTimeout / 1000)

						doReconnect(self)
					end
				else
					local _, _, op, args = string.find(message, OPERATION_PATTERN)

					if op ~= nil then
						if op == "ortc-validated" then
							local _, _, perms, set = string.find(args, VALIDATED_PATTERN)
							local statusC, errC

							if set ~= nil then
								sessionExpirationTime = set
							end

	


								if perms ~= nil then
									for channel, hash in string.gmatch(perms, PERMISSIONS_PATTERN) do
										permissions[channel] = hash
									end

									self.isConnected = true
									isConnecting = false
									isValid = true

									-- Subscribe to the previously subscribed channels
									for channel,channelSubscription in pairs(subscribedChannels) do
										-- Subscribe again
										if channelSubscription.subscribeOnReconnected and (channelSubscription.isSubscribing or channelSubscription.isSubscribed) then
											channelSubscription.isSubscribing = true
											channelSubscription.isSubscribed = false

											local domainChannelCharacterIndex = string.find(channel, ":")
											local channelToValidate = channel

											if domainChannelCharacterIndex ~= nil and domainChannelCharacterIndex > 0 then
												channelToValidate = string.sub(channel, 1, domainChannelCharacterIndex).."*"
											end

											local hash = (permissions[channel] ~= nil and permissions[channel] or permissions[channelToValidate] ~= nil and permissions[channelToValidate] or "")

											conn:send("\"subscribe;"..self.appKey..";"..self.authToken..";"..channel..";"..hash.."\"")
										end
									end

									-- Clean messages buffer (can have lost message parts in memory)
									messagesBuffer = {}

									if isReconnecting then
										isReconnecting = false
										delegateReconnectedCallback(self)
									else
										delegateConnectedCallback(self)
									end
								end
		
						elseif op == "ortc-subscribed" then
							local _, _, channel = string.find(args, CHANNEL_PATTERN)

							if subscribedChannels[channel] ~= nil then
								subscribedChannels[channel].isSubscribing = false
								subscribedChannels[channel].isSubscribed = true
							end

							delegateSubscribedCallback(self, channel)
						elseif op == "ortc-unsubscribed" then
							local _, _, channel = string.find(args, CHANNEL_PATTERN)

							delegateUnsubscribedCallback(self, channel)
						elseif op == "ortc-error" then
							local _, _, opException, chnException, msgException = string.find(args, EXCEPTION_PATTERN_2)

							if opException == nil then
								_, _, opException, msgException = string.find(args, EXCEPTION_PATTERN_1)
							end

							delegateExceptionCallback(self, msgException)

							if opException == "validate" then
								isValid = false

								doStopReconnecting()
							elseif opException == "subscribe" then
								if not Strings:isNullOrEmpty(chnException) then
                                    if subscribedChannels[chnException] then
                                        subscribedChannels[chnException].isSubscribing = false
                                    end
                                end
							elseif opException == "subscribe_maxsize" or opException == "unsubscribe_maxsize" or opException == "send_maxsize" then
								if not Strings:isNullOrEmpty(chnException) then
                                    if subscribedChannels[chnException] then
                                        subscribedChannels[chnException].isSubscribing = false
                                    end
                                end

								doStopReconnecting()

								self:disconnect()
							end
						end
					else
						local _, _, closeCode, closeReason = string.find(message, CLOSE_PATTERN)

						if closeCode == nil and closeReason == nil then
							local _, _, channel, messageReceived = string.find(message, RECEIVED_PATTERN)

							if subscribedChannels[channel] then
								messageReceived = string.gsub(string.gsub(messageReceived, "\\\\n", "\n"), "\\\\\\\"", "\"")

								-- Multi part
								local _, _, messageId, messageCurrentPart, messageTotalPart, plainTextMessage = string.find(messageReceived, MULTI_PART_MESSAGE_PATTERN)
								local lastPart = false;

								-- Is a message part
								if not Strings:isNullOrEmpty(messageId) and not Strings:isNullOrEmpty(messageCurrentPart) and not Strings:isNullOrEmpty(messageTotalPart) then
									if not messagesBuffer[messageId] then
										messagesBuffer[messageId] = {}
									end

									messagesBuffer[messageId][tonumber(messageCurrentPart)] = plainTextMessage

									-- Last message part
									if tostring(Strings:tableSize(messagesBuffer[messageId])) == messageTotalPart then
										lastPart = true
									end
								else -- Message does not have multipart, like the messages received at announcement channels
									lastPart = true
								end

								if lastPart then
									if not Strings:isNullOrEmpty(messageId) and not Strings:isNullOrEmpty(messageTotalPart) then
										messageReceived = "";

										for i = 1, messageTotalPart do
											messageReceived = messageReceived..messagesBuffer[messageId][i]

											-- Delete from messages buffer
											messagesBuffer[messageId][i] = nil
										end

										-- Delete from messages buffer
										messagesBuffer[messageId] = nil
									end

									subscribedChannels[channel].onMessageCallback(self, channel, messageReceived)
								end
							--else
								--print("RECEIVED:")
								--print(op)
								--print(args)
							end
						end
					end
				end
			end

		end
	end
end

-- constructor
function OrtcClient:new ()
  	local priv = {id, url, clusterUrl, connectionTimeout, isConnected, connectionMetadata, announcementSubChannel, sessionId, onConnected, onDisconnected, onSubscribed, onUnsubscribed, onException} -- private attributes in instance
  	local self = ProxyProperties:makeProxy(OrtcClient, priv, nil, attributeSetters, true)

  	-- Initialize random seed
  	math.randomseed(os.time())
	math.random()

	self.connectionTimeout = 5000 -- milliseconds
	self.isConnected = false

	sessionExpirationTime = 30 -- minutes

	isConnecting = false
	isReconnecting = false
	isCluster = false
	isValid = false
	stopReconnecting = false

	subscribedChannels = {}
	messagesBuffer = {}
	permissions = {}

	return self
end

--public
function OrtcClient:doConnect ()
	isConnecting = true

	if isCluster then
		local url = getClusterServer(self.clusterUrl)

		if url ~= nil then
			self.url = url
		else
			delegateExceptionCallback(self, "Unable to get URL from cluster")
		end
	end

	if self.url ~= nil then
		local uri = URI:new(self.url)

		local serverId = Strings:randomNumber(1, 1000)
		local connectionId = Strings:randomString(8)
		local prefix = (uri:scheme() == "https") and "wss" or "ws"

		connectionUrl = prefix.."://"..uri:host()..(uri:port() and ":"..uri:port() or "").."/broadcast/"..serverId.."/"..connectionId.."/websocket"

		local connectionUrl = URI:new(connectionUrl)
		local host = connectionUrl:host()
		local port = connectionUrl:port()
		local path = connectionUrl:path()

		conn = WebSocketConnection:new{}

		conn:connect(self, messageArrived, host, port, path)
	end
end

-- private
function OrtcClient:connect (applicationKey, authenticationToken)
	-- Sanity Checks
	if self.isConnected then
		delegateExceptionCallback(self, "Already connected")
	elseif Strings:isNullOrEmpty(self.clusterUrl) and Strings:isNullOrEmpty(self.url) then
		delegateExceptionCallback(self, "URL and Cluster URL are null or empty")
	elseif Strings:isNullOrEmpty(applicationKey) then
		delegateExceptionCallback(self, "Application Key is null or empty")
	elseif Strings:isNullOrEmpty(authenticationToken) then
		delegateExceptionCallback(self, "Authentication ToKen is null or empty")
	elseif not isCluster and not Strings:ortcIsValidUrl(self.url) then
		delegateExceptionCallback(self, "Invalid URL")
	elseif isCluster and not Strings:ortcIsValidUrl(self.clusterUrl) then
		delegateExceptionCallback(self, "Invalid Cluster URL")
	elseif not Strings:ortcIsValidInput(applicationKey) then
		delegateExceptionCallback(self, "Application Key has invalid characters")
	elseif not Strings:ortcIsValidInput(authenticationToken) then
		delegateExceptionCallback(self, "Authentication Token has invalid characters")
	elseif not Strings:ortcIsValidInput(self.announcementSubChannel) then
		delegateExceptionCallback(self, "Announcement Subchannel has invalid characters")
	elseif not Strings:isNullOrEmpty(self.connectionMetadata) and string.len(self.connectionMetadata) > MAX_CONNECTION_METADATA_SIZE then
		delegateExceptionCallback(self, "Connection metadata size exceeds the limit of "..MAX_CONNECTION_METADATA_SIZE.." characters")
	elseif isConnecting or isReconnecting then
		delegateExceptionCallback(self, "Already trying to connect")
	else
		if pcall(function ()
					if unexpected_condition then
						error()
					end

					if isCluster then
						URI:new(self.clusterUrl)
					else
						URI:new(self.url)
					end
				end) then
			stopReconnecting = false

			self.appKey = applicationKey
			self.authToken = authenticationToken

			self:doConnect()
		else
			delegateExceptionCallback(self, "Invalid URL")
		end
	end
end

-- private
function OrtcClient:subscribe (channel, subscribeOnReconnected, onMessageCallback)
	--Sanity Checks
	if not self.isConnected then
        delegateExceptionCallback(self, "Not connected")
	elseif Strings:isNullOrEmpty(channel) then
        delegateExceptionCallback(self, "Channel is null or empty")
	elseif not Strings:ortcIsValidInput(channel) then
		delegateExceptionCallback(self, "Channel has invalid characters")
    elseif subscribedChannels[channel] and subscribedChannels[channel].isSubscribing then
        delegateExceptionCallback(self, "Already subscribing to the channel "..channel)
    elseif subscribedChannels[channel] and subscribedChannels[channel].isSubscribed then
        delegateExceptionCallback(self, "Already subscribed to the channel "..channel)
    elseif string.len(channel) > MAX_CHANNEL_SIZE then
        delegateExceptionCallback(self, "Channel size exceeds the limit of "..MAX_CHANNEL_SIZE.." characters")
    else
		local domainChannelCharacterIndex = string.find(channel, ":")
		local channelToValidate = channel

		if domainChannelCharacterIndex ~= nil and domainChannelCharacterIndex > 0 then
			channelToValidate = string.sub(channel, 1, domainChannelCharacterIndex).."*"
		end

		local hash = (permissions[channel] ~= nil and permissions[channel] or permissions[channelToValidate] ~= nil and permissions[channelToValidate] or "")

		if Strings:tableSize(permissions) > 0 and Strings:isNullOrEmpty(hash) then
			delegateExceptionCallback(self, "No permission found to subscribe to the channel '"..channel.."'")
		else
			if not subscribedChannels[channel] then
				subscribedChannels[channel] = {}
			end

			subscribedChannels[channel].isSubscribing = true
			subscribedChannels[channel].isSubscribed = false
			subscribedChannels[channel].subscribeOnReconnected = subscribeOnReconnected
			subscribedChannels[channel].onMessageCallback = onMessageCallback

			conn:send("\"subscribe;"..self.appKey..";"..self.authToken..";"..channel..";"..hash.."\"")
		end
	end
end

-- private
function OrtcClient:unsubscribe (channel)
	--Sanity Checks
    if not self.isConnected then
        delegateExceptionCallback(self, "Not connected")
	elseif Strings:isNullOrEmpty(channel) then
        delegateExceptionCallback(self, "Channel is null or empty")
	elseif not Strings:ortcIsValidInput(channel) then
		delegateExceptionCallback(self, "Channel has invalid characters")
    elseif not subscribedChannels[channel] then
        delegateExceptionCallback(self, "Not subscribed to the channel "..channel)
    elseif string.len(channel) > MAX_CHANNEL_SIZE then
        delegateExceptionCallback(self, "Channel size exceeds the limit of "..MAX_CHANNEL_SIZE.." characters")
    else
		conn:send("\"unsubscribe;"..self.appKey..";"..channel.."\"")
	end
end

-- private
function OrtcClient:send (channel, message)
	--Sanity Checks
    if not self.isConnected then
        delegateExceptionCallback(self, "Not connected")
	elseif Strings:isNullOrEmpty(channel) then
        delegateExceptionCallback(self, "Channel is null or empty")
	elseif not Strings:ortcIsValidInput(channel) then
		delegateExceptionCallback(self, "Channel has invalid characters")
	elseif Strings:isNullOrEmpty(message) then
        delegateExceptionCallback(self, "Message is null or empty")
	elseif string.len(channel) > MAX_CHANNEL_SIZE then
        delegateExceptionCallback(self, "Channel size exceeds the limit of "..MAX_CHANNEL_SIZE.." characters")
	else
		local domainChannelCharacterIndex = string.find(channel, ":")
		local channelToValidate = channel

		if domainChannelCharacterIndex ~= nil and domainChannelCharacterIndex > 0 then
			channelToValidate = string.sub(channel, 1, domainChannelCharacterIndex).."*"
		end

		local hash = (permissions[channel] ~= nil and permissions[channel] or permissions[channelToValidate] ~= nil and permissions[channelToValidate] or "")

		if Strings:tableSize(permissions) > 0 and Strings:isNullOrEmpty(hash) then
			delegateExceptionCallback(self, "No permission found to send to the channel '"..channel.."'")
		else
			message = string.gsub(string.gsub(message, "\\", "\\\\"), "\\\\n", "\\n")

			local messageParts = {}
			local messageId = Strings:generateId(8)

			-- Multi part
			local allowedMaxSize = MAX_MESSAGE_SIZE - string.len(channel);
			local i = 1
			local index = 1

			while i < string.len(message) do
				-- Just one part
				if string.len(message) <= allowedMaxSize then
					messageParts[index] = message
					break
				end

				if string.sub(message, i, i + allowedMaxSize) then
					messageParts[index] = string.sub(message, i, i + allowedMaxSize)
				end

				i = i + allowedMaxSize
				index = index + 1
			end

			for j = 1, Strings:tableSize(messageParts) do
				conn:send("\"send;"..self.appKey..";"..self.authToken..";"..channel..";"..hash..";"..messageId.."_"..j.."-"..Strings:tableSize(messageParts).."_"..messageParts[j].."\"")
			end
		end
	end
end

-- private
function OrtcClient:disconnect ()
	doStopReconnecting()

	-- Clear subscribed channels
	subscribedChannels = {}

	--Sanity Checks
    if not self.isConnected then
        delegateExceptionCallback(self, "Not connected")
	else
		conn:disconnect()
	end
end

-- private
function OrtcClient:isSubscribed (channel)
	result = nil

	--Sanity Checks
    if not self.isConnected then
        delegateExceptionCallback(self, "Not connected")
	elseif Strings:isNullOrEmpty(channel) then
        delegateExceptionCallback(self, "Channel is null or empty")
	elseif not Strings:ortcIsValidInput(channel) then
		delegateExceptionCallback(self, "Channel has invalid characters")
	else
		result = subscribedChannels[channel] and subscribedChannels[channel].isSubscribed and true or false
	end

	return result
end

-- private
function OrtcClient:saveAuthentication (url, isCluster, authenticationToken, authenticationTokenIsPrivate, applicationKey, timeToLive, privateKey, permissions, callback)
	local result = false
	local newUrl = nil
	local err = nil

	if isCluster then
		newUrl = getClusterServer(url)

		if newUrl == nil then
			delegateExceptionCallback(self, "Unable to get URL from cluster")
		end
	else
		newUrl = url
	end

	if newUrl ~= nil then
		newUrl = (string.sub(newUrl, string.len(url)) == "/" and newUrl or (newUrl.."/")).."authenticate"

		local body = "AT="..authenticationToken.."&PVT="..(authenticationTokenIsPrivate and "1" or "0").."&AK="..applicationKey.."&TTL="..timeToLive.."&PK="..privateKey.."&TP="..Strings:tableSize(permissions)

		if permissions ~= nil then
			for k,v in pairs(permissions) do
				body = body.."&"..k.."="..v
			end
		end

		local response, code = http.request(newUrl, body)

		if code == 200 or code == 201 then
			result = true
		else
			err = response
		end

		callback(err, result)
	end
end
