local http = require("socket.http")
local ltn12 = require("ltn12")
require("ualove.init")

local function drawStatus(s)
	love.graphics.clear()
	love.graphics.print(s, 2, 595)
	love.graphics.present()
end

local oldrun = love.run
function love.run()
	drawStatus("Getting update info...")
	-- load the config in this .love file
	local conf = {}
	do
		local f = assert(love.filesystem.load("updconf.lua"))
		setfenv(f, conf)
		f()
	end
	-- yes, github
	local baseurl = ("http://github.com/%s/%s/"):format(conf.author, conf.repo)
	local manifestinfo = {}
	do
		local s = http.request(baseurl..("raw/upd/manifest.lua"))
		local f = assert(loadstring(s))
		setfenv(f, manifestinfo)
		f()
	end
	-- this can be changed but I don't see any reason why
	love.filesystem.setIdentity(("game-%s-%s"):format(conf.author, conf.repo))
	local dir = love.filesystem.getSaveDirectory().."/"
	local curVer = 000
	do
		if love.filesystem.exists("/updmanifest.lua") then
			-- there's already a version installed!
			local t = {}
			local f = assert(loadfile(dir.."updmanifest.lua"))
			setfenv(f, t)
			f()
			curVer = t.version
		end
	end
	love.filesystem.write("updmanifest.lua", "") -- hack to create the save directory...
	local latestVer = curVer
	do
		local versions,updVers = manifestinfo.versions,{}
		for k=1,#versions do
			local ver,veri = versions[k],{}
			if ver > curVer then
				-- we only need to download the manifests of more recent versions
				local s = http.request(baseurl..("raw/upd/manifest-%03d.lua"):format(ver))
				local f = assert(loadstring(s))
				setfenv(f, veri)
				f()
				veri.version = ver
				updVers[#updVers+1] = veri
				latestVer = ver
			end
		end
		manifestinfo.versions = updVers
	end
	if curVer < latestVer then
		-- time to do stuff
		love.graphics.clear()
		drawStatus((curVer == 000 and "Downloading game...") or "Downloading update...")
		love.graphics.present()
		local filesToDownload,filesToRemove = {},{}
		local versions = manifestinfo.versions
		local latestTag = versions[#versions].tag
		if curVer == 000 then
			-- just download everything
			filesToDownload = versions[#versions].files
		else
			for k=1,#versions do
				local ver = versions[k]
				for name in pairs(ver.updated) do
					filesToDownload[name] = true
				end
				for name in pairs(ver.removed) do
					filesToRemove[name] = true
				end
			end
		end
		for name in pairs(filesToDownload) do
			local url = ("%sraw/%s/%s"):format(baseurl, latestTag, name)
			if name:find("^.+/") then
				-- not sure if this works with multiple non-existant directories but that shouldn't happen so w/e
				local fdir = name:sub(name:find("^.+/"))
				love.filesystem.mkdir(fdir)
			end
			print(url, http.request{
				url = url,
				sink = ltn12.sink.file(io.open(dir..name, "w"..(name:sub(-4) ~= ".lua" and "b" or "")))
			})
		end
		for name in pairs(filesToRemove) do
			love.filesystem.remove(name)
		end
	end
	love.filesystem.write("updmanifest.lua", ("version = %03d"):format(latestVer))
	-- load the game
	love.filesystem.load("main.lua")()
	-- run the game with UaLove (har har, vendor lock-in)
	oldrun()
end