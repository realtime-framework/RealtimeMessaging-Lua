Strings = {}
Strings.__index = Strings

local chars = {}

for loop = 0, 255 do
   chars[loop + 1] = string.char(loop)
end

local charsTable = table.concat(chars)

local built = {['.'] = chars}

-- private
local addLookup = function(charSet)
   local substitute = string.gsub(charsTable, '[^'..charSet..']', '')
   local lookup = {}

   for loop = 1, string.len(substitute) do
       lookup[loop] = string.sub(substitute, loop, loop)
   end

   built[charSet] = lookup

   return lookup
end

-- public
function Strings:trim (s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- public
function Strings:randomNumber (min, max)
    return math.random(min, max)
end

-- public
function Strings:randomString (length)
   	local charSet = "abcdefghijklmnopqrstuvwxyz"

  	local result = {}
  	local lookup = built[charSet] or addLookup(charSet)
  	local range = table.getn(lookup)

  	for loop = 1, length do
     	result[loop] = lookup[math.random(1, range)]
  	end

  	return table.concat(result)
end

-- public
function Strings:generateId (size)
	local charSet = "abcdefghijklmnopqrstuvwxyz0123456789"

  	local result = {}
  	local lookup = built[charSet] or addLookup(charSet)
  	local range = table.getn(lookup)

  	for loop = 1, size do
     	result[loop] = lookup[math.random(1, range)]
  	end

  	return table.concat(result)
end

-- public
function Strings:isNullOrEmpty (input)
	local result = false

	if input == nil or input == "" then
		result = true
	end

	return result
end

--public
function Strings:tableSize (myTable)
	numItems = 0

	if myTable ~= nil then
		for k,v in pairs(myTable) do
			numItems = numItems + 1
		end
	end

	return numItems
end

-- public
function Strings:ortcIsValidUrl (input)
	return string.match(input, "^%s*http[s]?://%w?+?:?%w?*?@?(%S+):?[0-9]?+?/?[%w#!:.?+=&%@!\-/]?%s*$") and true or false
end

-- public
function Strings:ortcIsValidInput (input)
	return (input == nil or string.match(input, "^[%w-:/.]*$")) and true or false
end
