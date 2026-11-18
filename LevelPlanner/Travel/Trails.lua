-- Trails: the ground you have actually walked, so the arrow can lead you round mountains, up the right
-- ramp and through the gap, instead of straight at a cliff.
--   * Recording: twice a second on foot, the 20-yard squares you pass through and a ONE-WAY link
--     from each to the next (you can jump down a cliff you can't walk up, so the way back is only
--     known once you've walked it). Kept in LevelPlannerDB.trails, shared by your characters.
--   * Finding a way: shortest path over those links (A*), from squares near you to squares near the
--     target. Where you have never walked there is no trail, and the arrow points straight as before.
-- No outside data: every trail is one you (or another character of yours) walked.
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local T = {}
ns.Trails = T

local CELL = 20          -- yards per square
local NEAR = 3           -- squares around a point searched for the trail's ends (60 yd)
local MAX_EXPAND = 20000 -- A* gives up after this many squares (a far target off your trails)

local function db()
	local d = ns.db
	d.trails = d.trails or {}
	return d.trails
end

local function cellOf(wx, wy) return math.floor(wx / CELL), math.floor(wy / CELL) end
local function keyOf(cx, cy) return cx .. ":" .. cy end
local function parse(k) local x, y = k:match("^(-?%d+):(-?%d+)$") return tonumber(x), tonumber(y) end
local function centre(cx, cy) return (cx + 0.5) * CELL, (cy + 0.5) * CELL end

----------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------
local prev -- { inst, cx, cy, wx, wy }
local added = 0

local function link(g, a, b)
	local e = g[a]
	if not e then e = {} g[a] = e added = added + 1 end
	if not e[b] then e[b] = 1 end
	if not g[b] then g[b] = {} added = added + 1 end
end

function T.Sample()
	if ns.cfg.trails == false then prev = nil return end
	local p = ns.Geo.PlayerPoint()
	local _, kind = IsInInstance()
	if not p or not p.inst or UnitOnTaxi("player") or (kind and kind ~= "none")
		or (UnitIsDead("player") and not UnitIsGhost("player")) then
		prev = nil
		return
	end
	local cx, cy = cellOf(p.wx, p.wy)
	if prev and prev.inst == p.inst then
		local dx, dy = p.wx - prev.wx, p.wy - prev.wy
		local d = math.sqrt(dx * dx + dy * dy)
		if d > 40 then prev = nil end -- a teleport, a summon or a loading screen: no link
	else
		prev = nil
	end
	if prev and (cx ~= prev.cx or cy ~= prev.cy) then
		local g = db()[p.inst] or {}
		db()[p.inst] = g
		-- the squares between the two samples, in order
		local dx, dy = p.wx - prev.wx, p.wy - prev.wy
		local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / (CELL / 2)))
		local lastKey = keyOf(prev.cx, prev.cy)
		for i = 1, steps do
			local ix, iy = cellOf(prev.wx + dx * i / steps, prev.wy + dy * i / steps)
			local k = keyOf(ix, iy)
			if k ~= lastKey then link(g, lastKey, k) lastKey = k end
		end
	end
	prev = { inst = p.inst, cx = cx, cy = cy, wx = p.wx, wy = p.wy }
end

----------------------------------------------------------------------------------------
-- Finding a way (A*)
----------------------------------------------------------------------------------------
-- A small binary heap of {f, key}.
local function push(h, f, k)
	local n = #h + 1
	h[n] = { f, k }
	while n > 1 do
		local p = math.floor(n / 2)
		if h[p][1] <= h[n][1] then break end
		h[p], h[n] = h[n], h[p]
		n = p
	end
end
local function pop(h)
	local top = h[1]
	local last = table.remove(h)
	if #h > 0 then
		h[1] = last
		local n = 1
		while true do
			local l, r, s = n * 2, n * 2 + 1, n
			if h[l] and h[l][1] < h[s][1] then s = l end
			if h[r] and h[r][1] < h[s][1] then s = r end
			if s == n then break end
			h[s], h[n] = h[n], h[s]
			n = s
		end
	end
	return top
end

-- Trail squares within NEAR squares of a point: { key = straight distance from the point }.
local function nearby(g, wx, wy)
	local cx, cy = cellOf(wx, wy)
	local out, any = {}, false
	for x = cx - NEAR, cx + NEAR do
		for y = cy - NEAR, cy + NEAR do
			local k = keyOf(x, y)
			if g[k] then
				local mx, my = centre(x, y)
				local d = math.sqrt((mx - wx) ^ 2 + (my - wy) ^ 2)
				if d <= NEAR * CELL then out[k] = d any = true end
			end
		end
	end
	return any and out or nil
end

-- A way from point a to point b along your trails: a list of points (with wx, wy, inst), from a to
-- b, and its length in yards. nil when the trails don't connect them (or they're close anyway).
function T.Path(a, b)
	if ns.cfg.trails == false or not (a and b) or a.inst ~= b.inst then return nil end
	local g = db()[a.inst]
	if not g then return nil end
	local straight = ns.Geo.Distance(a, b)
	if not straight or straight < (ns.cfg.trailMinYards or 80) then return nil end
	local starts, goals = nearby(g, a.wx, a.wy), nearby(g, b.wx, b.wy)
	if not (starts and goals) then return nil end

	local gScore, from, open, closed = {}, {}, {}, {}
	local function h(k)
		local x, y = parse(k)
		local mx, my = centre(x, y)
		return math.sqrt((mx - b.wx) ^ 2 + (my - b.wy) ^ 2)
	end
	for k, d in pairs(starts) do
		gScore[k] = d
		push(open, d + h(k), k)
	end
	local best, bestTotal
	local expanded = 0
	while #open > 0 and expanded < MAX_EXPAND do
		local f, k = unpack(pop(open))
		if not closed[k] then
			closed[k] = true
			expanded = expanded + 1
			if bestTotal and f >= bestTotal then break end
			local gk = gScore[k]
			if goals[k] then
				local total = gk + goals[k]
				if not bestTotal or total < bestTotal then best, bestTotal = k, total end
			end
			local x, y = parse(k)
			local mx, my = centre(x, y)
			for n in pairs(g[k] or {}) do
				if not closed[n] then
					local nx, ny = parse(n)
					local ox, oy = centre(nx, ny)
					local ng = gk + math.sqrt((ox - mx) ^ 2 + (oy - my) ^ 2)
					if not gScore[n] or ng < gScore[n] then
						gScore[n], from[n] = ng, k
						push(open, ng + h(n), n)
					end
				end
			end
		end
	end
	if not best then return nil end
	-- a long way round is fine (that's the point), but not an absurd one
	if bestTotal > straight * (ns.cfg.trailMaxDetour or 1.8) then return nil end

	local keys = {}
	local k = best
	while k do table.insert(keys, 1, k) k = from[k] end
	local pts = { a }
	for _, key in ipairs(keys) do
		local x, y = parse(key)
		local wx, wy = centre(x, y)
		pts[#pts + 1] = { wx = wx, wy = wy, inst = a.inst }
	end
	pts[#pts + 1] = b
	return pts, bestTotal
end

-- Where to steer now on the way to b: a point about `ahead` yards along the trail, and the
-- trail's length left. nil when there is no trail (steer straight at b).
function T.Steer(a, b, ahead)
	local pts, len = T.Path(a, b)
	if not pts then return nil end
	ahead = ahead or 40
	for i = 2, #pts do
		local d = ns.Geo.Distance(a, pts[i])
		if d and d >= ahead then return pts[i], len end
	end
	return b, len
end

function T.Count()
	local squares = 0
	for _, g in pairs(db()) do for _ in pairs(g) do squares = squares + 1 end end
	return squares
end

function T.Init()
	C_Timer.NewTicker(0.5, function() ns.safe(T.Sample) end)
end
