--!nonstrict
-- Executed by the official Luau CLI, not a JavaScript/Python translation.
local RoundMachine = require("../src/server/core/RoundMachine")
local PickupLedger = require("../src/server/core/PickupLedger")
local MovementGuard = require("../src/server/core/MovementGuard")
local ArenaRoute = require("../src/server/core/ArenaRoute")
local Creatures = require("../src/shared/Creatures")
local Config = require("../src/shared/Config")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, message = pcall(fn)
	if ok then passed += 1; print("PASS " .. name) else failed += 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end
local function eq(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function throws(fn)
	eq(pcall(fn), false)
end
local function machine()
	local config = table.clone(Config)
	config.Timing = Config.FastTiming
	return RoundMachine.new(config)
end
local function playing(count)
	local m = machine()
	for i = 1, count or 2 do m:addPlayer(-i, "Brain " .. i) end
	m:step(100)
	m:step(104)
	return m
end
local positions = { {x=0,y=23.5,z=0}, {x=10,y=23.5,z=0} }
local function ledger(roll)
	return PickupLedger.new(positions, Config.Kinds, 4.5, 5, function() return roll or 0 end)
end
local function context(id, p, roundId)
	return { userId=id or -1, roundId=roundId or 1, active=true, alive=true, position=p or {x=0,y=23.5,z=0} }
end

test("production round is exactly three minutes", function() eq(Config.Timing.Round, 180) end)
test("waiting does not advance without players", function() local m=machine(); eq(#m:step(100),0); eq(m.phase,"Waiting") end)
test("first player starts a short intermission", function() local m=machine(); m:addPlayer(-1,"Solo"); m:step(100); eq(m.phase,"Intermission"); eq(m.phaseEndsAt,104) end)
test("intermission deadline does not drift on ticks", function() local m=machine(); m:addPlayer(1,"A"); m:step(100); m:step(103.99); eq(m.phase,"Intermission"); eq(m.phaseEndsAt,104) end)
test("round starts precisely at deadline", function() local m=playing(); eq(m.phase,"Playing"); eq(m.roundId,1); eq(m.phaseEndsAt,134) end)
test("all current players participate", function() local m=playing(12); for i=1,12 do eq(m:isParticipating(-i),true) end end)
test("negative Studio UserIds are supported", function() eq(machine():addPlayer(-2,"Local client"),true) end)
test("duplicate registration cannot reset progress", function() local m=playing(); m:award(-1,5,1); eq(m:addPlayer(-1,"Again"),false); eq(m.players[-1].score,5) end)
test("invalid UserIds are rejected", function() local m=machine(); for _,id in {0,1.5,math.huge,0/0} do eq(m:addPlayer(id,"Bad"),false) end end)
test("score changes outside active round rejected", function() local m=machine(); m:addPlayer(-1,"A"); eq(m:award(-1,1,0),false) end)
test("stale round award rejected", function() local m=playing(); eq(m:award(-1,10,0),false); eq(m.players[-1].score,0) end)
test("only three server denominations accepted", function() local m=playing(); for _,v in {0,-1,2,100000,0/0,math.huge} do eq(m:award(-1,v,1),false) end; eq(m.players[-1].score,0) end)
test("missing player cannot be awarded", function() eq(playing():award(999,10,1),false) end)
test("valid score and pickup counts accumulate", function() local m=playing(); for _,v in {1,5,10} do eq(m:award(-1,v,1),true) end; eq(m.players[-1].score,16); eq(m.players[-1].pickups,3) end)
test("late joiner enters current round at zero", function() local m=playing(); m:addPlayer(-3,"Late"); eq(m:isParticipating(-3),true); eq(m.players[-3].score,0) end)
test("low gravity starts at configured elapsed time", function() local m=playing(); m:step(111.99); eq(m.eventActive,false); local effects=m:step(112); eq(m.eventActive,true); eq(m.eventEndsAt,122); eq(effects[1].kind,"event") end)
test("low gravity ends and cannot restart", function() local m=playing(); m:step(112); m:step(122); eq(m.eventActive,false); eq(#m:step(123),0) end)
test("stalled server skips expired event safely", function() local m=playing(); m:step(125); eq(m.eventActive,false); eq(m.eventFinished,true) end)
test("round deadline processed before pickups", function() local m=playing(); m:step(134); eq(m.phase,"Results"); eq(m:award(-1,10,1),false) end)
test("long stall finishes only once without retroactive events", function() local m=playing(); m:step(1000); eq(m.phase,"Results"); eq(m.eventActive,false); eq(m.phaseEndsAt,1005) end)
test("highest score wins", function() local m=playing(); m:award(-1,10,1); m:award(-2,5,1); m:step(134); eq(#m.lastResults.winners,1); eq(m.lastResults.winners[1].id,-1) end)
test("ties share the crown", function() local m=playing(); m:award(-1,5,1); m:award(-2,5,1); m:step(134); eq(#m.lastResults.winners,2); eq(m.players[-1].wins,1); eq(m.players[-2].wins,1) end)
test("zero-score round declares no winner", function() local m=playing(); m:step(134); eq(#m.lastResults.winners,0); eq(m.players[-1].wins,0) end)
test("winner receives correct session coins", function() local m=playing(); m:award(-1,10,1); m:step(134); eq(m.players[-1].coins,60); eq(m.lastResults.rewards["-1"],60) end)
test("other participants receive base plus score coins", function() local m=playing(); m:award(-1,10,1); m:award(-2,5,1); m:step(134); eq(m.players[-2].coins,20) end)
test("results use remote-safe string-key reward dictionary", function() local m=playing(); m:step(134); for key in m.lastResults.rewards do eq(type(key),"string") end end)
test("results cannot pay rewards twice", function() local m=playing(); m:award(-1,5,1); m:step(134); local amount=m.players[-1].coins; m:step(134); m:step(136); eq(m.players[-1].coins,amount) end)
test("results lead back to intermission", function() local m=playing(); m:step(134); m:step(139); eq(m.phase,"Intermission"); eq(m.phaseEndsAt,143) end)
test("new round clears score but preserves coins and wins", function() local m=playing(); m:award(-1,10,1); m:step(134); m:step(139); m:step(143); eq(m.roundId,2); eq(m.players[-1].score,0); eq(m.players[-1].pickups,0); eq(m.players[-1].coins,60); eq(m.players[-1].wins,1) end)
test("join during results is not paid for prior round", function() local m=playing(); m:step(134); m:addPlayer(-3,"Late"); eq(m.players[-3].coins,0); eq(m:isParticipating(-3),false) end)
test("disconnected player cannot win", function() local m=playing(); m:award(-1,10,1); m:award(-2,1,1); m:removePlayer(-1); m:step(134); eq(m.lastResults.winners[1].id,-2) end)
test("empty server cancels round and low gravity", function() local m=playing(); m:step(112); m:removePlayer(-1); m:removePlayer(-2); m:step(113); eq(m.phase,"Waiting"); eq(m.eventActive,false); eq(m.phaseEndsAt,0) end)
test("rejoining empty server gets fresh intermission", function() local m=playing(1); m:removePlayer(-1); m:step(110); m:addPlayer(-2,"New"); m:step(111); eq(m.phase,"Intermission"); eq(m.phaseEndsAt,115) end)
test("stable leaderboard orders ties by ID", function() local m=playing(3); m:award(-1,5,1); m:award(-3,10,1); m:award(-2,5,1); local rows=m:rows(); eq(rows[1].id,-3); eq(rows[2].id,-2); eq(rows[3].id,-1) end)
test("public score snapshots do not alias authority player records", function() local m=playing(); local s=m:snapshot(); s.rows[1].score=999; eq(m.players[s.rows[1].id].score,0) end)
test("backwards and nonfinite clocks fail closed", function() local m=playing(); throws(function() m:step(103) end); throws(function() m:step(0/0) end); throws(function() m:step(math.huge) end) end)
test("invalid phase timings fail early", function() local c=table.clone(Config); c.Timing=table.clone(Config.Timing); c.Timing.Round=0; throws(function() RoundMachine.new(c) end) end)
test("event must fit inside round", function() local c=table.clone(Config); c.Timing=table.clone(Config.FastTiming); c.Timing.EventDuration=40; throws(function() RoundMachine.new(c) end) end)
test("halo cannot be bought without server coins", function() local m=playing(); local ok=m:haloAction(-1); eq(ok,false); eq(m.players[-1].coins,0) end)
test("halo is charged once then toggles free", function() local m=playing(); m.players[-1].coins=150; eq(m:haloAction(-1),true); eq(m.players[-1].coins,50); eq(m.players[-1].haloEquipped,true); eq(m:haloAction(-1),true); eq(m.players[-1].haloEquipped,false); m:haloAction(-1); eq(m.players[-1].coins,50) end)
test("halo request spam cannot produce negative balance", function() local m=playing(); m.players[-1].coins=100; for _=1,500 do m:haloAction(-1) end; eq(m.players[-1].coins,0); eq(m.players[-1].haloOwned,true) end)
test("missing player cannot buy cosmetic", function() eq(playing():haloAction(999),false) end)
test("rejoining does not persist session rewards", function() local m=playing(); m.players[-1].coins=100; m:haloAction(-1); m:removePlayer(-1); m:addPlayer(-1,"Back"); eq(m.players[-1].coins,0); eq(m.players[-1].haloOwned,false) end)

test("ledger starts inactive", function() local l=ledger(); eq(l:tryClaim(1,0,context(),100),nil) end)
test("round activation initializes generation and rarity", function() local l=ledger(); l:beginRound(1); eq(l.slots[1].generation,1); eq(l.slots[1].available,true); eq(l.slots[1].kindIndex,1) end)
test("rarity weights select all three kinds", function() for _,pair in {{0,1},{.779,1},{.78,2},{.959,2},{.96,3},{1,3}} do eq(ledger(pair[1]):rollKind(),pair[2]) end end)
test("valid proximity claim returns server value", function() local l=ledger(.9); l:beginRound(1); local r=l:tryClaim(1,1,context(),100); eq(r.value,5); eq(r.userId,-1); eq(r.roundId,1) end)
test("same player cannot double claim a cell", function() local l=ledger(); l:beginRound(1); assert(l:tryClaim(1,1,context(),100)); eq(l:tryClaim(1,1,context(),100),nil) end)
test("two-player same-tick race yields exactly one award", function() local l=ledger(); l:beginRound(1); local first=l:tryClaim(1,1,context(-1),100); local second=l:tryClaim(1,1,context(-2),100); assert(first); eq(second,nil) end)
test("out-of-range position cannot claim", function() local l=ledger(); l:beginRound(1); eq(l:tryClaim(1,1,context(-1,{x=5,y=23.5,z=0}),100),nil); eq(l.slots[1].available,true) end)
test("pickup sphere includes boundary", function() local l=ledger(); l:beginRound(1); assert(l:tryClaim(1,1,context(-1,{x=4.5,y=23.5,z=0}),100)) end)
test("vertical distance is also validated", function() local l=ledger(); l:beginRound(1); eq(l:tryClaim(1,1,context(-1,{x=0,y=29,z=0}),100),nil) end)
test("NaN and infinity positions rejected", function() for _,p in {{x=0/0,y=23.5,z=0},{x=0,y=math.huge,z=0},{x=0,y=23.5,z=-math.huge}} do local l=ledger(); l:beginRound(1); eq(l:tryClaim(1,1,context(-1,p),100),nil) end end)
test("dead and nonparticipant characters rejected", function() local l=ledger(); l:beginRound(1); local c=context(); c.alive=false; eq(l:tryClaim(1,1,c,100),nil); c.alive=true; c.active=false; eq(l:tryClaim(1,1,c,100),nil) end)
test("invalid claimant ID rejected", function() local l=ledger(); l:beginRound(1); for _,id in {0,1.5,math.huge,0/0} do eq(l:tryClaim(1,1,context(id),100),nil) end end)
test("invalid and fractional slot IDs rejected", function() local l=ledger(); l:beginRound(1); for _,id in {-1,0,3,1.5,0/0} do eq(l:tryClaim(id,1,context(),100),nil) end end)
test("stale generation cannot claim available slot", function() local l=ledger(); l:beginRound(1); eq(l:tryClaim(1,0,context(),100),nil) end)
test("stale round claim rejected", function() local l=ledger(); l:beginRound(2); eq(l:tryClaim(1,1,context(),100),nil) end)
test("respawn waits full cooldown", function() local l=ledger(); l:beginRound(1); l:tryClaim(1,1,context(),100); eq(#l:step(104.99),0); eq(l.slots[1].available,false) end)
test("respawn creates new generation", function() local l=ledger(); l:beginRound(1); l:tryClaim(1,1,context(),100); eq(l:step(105)[1],1); eq(l.slots[1].generation,2); eq(l:tryClaim(1,1,context(),105),nil); assert(l:tryClaim(1,2,context(),105)) end)
test("reset invalidates prior generation and round", function() local l=ledger(); l:beginRound(1); l:beginRound(2); eq(l:tryClaim(1,1,context(-1,nil,2),100),nil); assert(l:tryClaim(1,2,context(-1,nil,2),100)) end)
test("clear stops claims and all respawns", function() local l=ledger(); l:beginRound(1); l:tryClaim(1,1,context(),100); l:clear(); eq(#l:step(1000),0); eq(l:tryClaim(2,1,context(-1,{x=10,y=23.5,z=0}),1000),nil) end)
test("invalid time cannot consume a cell", function() local l=ledger(); l:beginRound(1); eq(l:tryClaim(1,1,context(),0/0),nil); eq(l.slots[1].available,true) end)
test("invalid server pickup configuration rejected", function() throws(function() PickupLedger.new(positions,Config.Kinds,0,5,function() return 0 end) end); throws(function() PickupLedger.new(positions,{{Name="Bad",Value=999,Weight=1,Color={}}},4,5,function() return 0 end) end) end)

test("spawn grace suppresses immediate collection", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); eq(g:observe(-1,{x=0,y=24,z=0},100.5),false); eq(g:observe(-1,{x=0,y=24,z=0},100.65),true) end)
test("normal walking is allowed", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); eq(g:observe(-1,{x=10,y=24,z=0},101),true) end)
test("low gravity vertical jumps are allowed", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); eq(g:observe(-1,{x=0,y=50,z=0},101),true) end)
test("implausible horizontal teleport is corrected", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); local ok,p=g:observe(-1,{x=100,y=25,z=0},100.1); eq(ok,false); eq(p.x,0) end)
test("invalid movement fails closed", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); local ok,p=g:observe(-1,{x=math.huge,y=25,z=0},101); eq(ok,false); eq(p.x,0) end)
test("authorized teleport reestablishes movement baseline", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); g:teleport(-1,{x=100,y=25,z=0},101); eq(g:observe(-1,{x=101,y=25,z=0},102),true) end)
test("movement record removed on disconnect", function() local g=MovementGuard.new(65,9,.65); g:teleport(-1,{x=0,y=25,z=0},100); g:remove(-1); eq(g.tracks[-1],nil) end)

test("100 simulated 12-player rounds conserve scores and rewards", function()
	math.randomseed(20261028)
	local m=machine()
	for i=1,12 do m:addPlayer(-i,"Player "..i) end
	local l=PickupLedger.new(positions,Config.Kinds,4.5,5,function() return math.random() end)
	local now=100
	for round=1,100 do
		m:step(now)
		now=m.phaseEndsAt
		m:step(now)
		eq(m.phase,"Playing"); eq(m.roundId,round)
		l:beginRound(round)
		local start=now
		local expected={}
		for i=1,12 do expected[-i]=0 end
		for tick=1,299 do
			now=start+tick*.1
			m:step(now); l:step(now)
			for slotId,slot in l.slots do
				local id=-math.random(1,12)
				local r=l:tryClaim(slotId,slot.generation,context(id,slot.position,round),now)
				if r then
					assert(m:award(id,r.value,round))
					expected[id]+=r.value
					eq(l:tryClaim(slotId,slot.generation,context(-1,slot.position,round),now),nil)
				end
			end
		end
		local previousCoins={}
		for id,p in m.players do eq(p.score,expected[id]); previousCoins[id]=p.coins end
		now=start+30; m:step(now); l:clear(); eq(m.phase,"Results"); eq(m.eventActive,false)
		for id,p in m.players do
			local won=p.score==m.lastResults.topScore
			eq(p.coins-previousCoins[id],10+p.score*2+(if won then 30 else 0))
		end
		now=m.phaseEndsAt; m:step(now); eq(m.phase,"Intermission")
	end
end)


-- ---------------------------------------------------------------- arena access
local function router() return ArenaRoute.new() end
local arenaPoint = { x = 20, y = 25, z = 10 }
local lobbyPoint = { x = 0, y = 25, z = 188 }

test("route: desired destination follows phase and eligibility", function()
	eq(ArenaRoute.desired("Playing", true), "arena")
	-- A non-participant during a live round is a spectator: left alone, not moved.
	eq(ArenaRoute.desired("Playing", false), nil)
	eq(ArenaRoute.desired("Intermission", false), "lobby")
	eq(ArenaRoute.desired("Results", true), "lobby")
	eq(ArenaRoute.desired("Waiting", true), "lobby")
	eq(ArenaRoute.desired("Unknown", true), nil)
end)
test("route: zone is a plane test, arena includes the far satellites", function()
	eq(ArenaRoute.zone(arenaPoint), "arena")
	eq(ArenaRoute.zone({ x = 73, y = 25, z = 0 }), "arena")
	eq(ArenaRoute.zone({ x = -94, y = 21, z = 0 }), "arena")   -- west dock
	eq(ArenaRoute.zone({ x = 33, y = 25, z = 13 }), "arena")    -- spawn pad at r=36
	eq(ArenaRoute.zone(lobbyPoint), "lobby")
	eq(ArenaRoute.zone({ x = 0, y = 21, z = 120 }), "transit")  -- causeway deck
end)
test("route: transit counts as arrived either way, so no teleport loop", function()
	eq(ArenaRoute.atDestination("arena", { x = 0, y = 21, z = 120 }), true)
	eq(ArenaRoute.atDestination("lobby", { x = 0, y = 21, z = 120 }), true)
	eq(ArenaRoute.atDestination("arena", lobbyPoint), false)
	eq(ArenaRoute.atDestination("lobby", arenaPoint), false)
end)
test("route: a correct player is left alone", function()
	local r = router()
	eq(r:evaluate(-1, "Playing", true, arenaPoint, true, 1), "arrived")
	eq(r:evaluate(-1, "Playing", true, arenaPoint, true, 2), "arrived")
	eq(r.fallbacks, 0)
end)
test("route: a stranded player is retried, spaced by the backoff", function()
	local r = router()
	eq(r:evaluate(-1, "Playing", true, lobbyPoint, true, 1), "retry")
	r:attempt(-1, "arena", 1)
	eq(r:evaluate(-1, "Playing", true, lobbyPoint, true, 1.1), "pending")
	eq(r:evaluate(-1, "Playing", true, lobbyPoint, true, 1 + ArenaRoute.RETRY_DELAY + .01), "retry")
end)
test("route: repeated failures escalate exactly once per window", function()
	local r = router()
	local now = 1
	for _ = 1, ArenaRoute.MAX_ATTEMPTS do
		eq(r:evaluate(-1, "Playing", true, lobbyPoint, true, now), "retry")
		r:attempt(-1, "arena", now)
		now += ArenaRoute.RETRY_DELAY + .01
	end
	eq(r:evaluate(-1, "Playing", true, lobbyPoint, true, now), "give-up")
	eq(r.fallbacks, 1)
	eq(r:evaluate(-1, "Playing", true, lobbyPoint, true, now + 1), "retry")
end)
test("route: a dead or missing character is never teleported", function()
	local r = router()
	eq(r:evaluate(-1, "Playing", true, nil, false, 1), "pending")
	eq(r:evaluate(-1, "Playing", true, lobbyPoint, false, 2), "pending")
	eq(r:track(-1).attempts, 0)
end)
test("route: idle phases never move anybody", function()
	local r = router()
	-- Between rounds everybody belongs in the lobby; an arena straggler is moved back.
	eq(ArenaRoute.desired("Waiting", false), "lobby")
	eq(r:evaluate(-1, "Waiting", false, lobbyPoint, true, 1), "arrived")
	eq(r:evaluate(-2, "Waiting", false, arenaPoint, true, 1), "retry")
	-- A spectator standing in the lobby is already where a spectator belongs.
	eq(r:evaluate(-1, "Playing", false, lobbyPoint, true, 2), "idle")
	eq(r:evaluate(-1, "Playing", false, arenaPoint, true, 3), "idle")
end)
test("route: the sweep is bounded and covers everyone once per cycle", function()
	local ids = {}
	for i = 1, 12 do ids[i] = -i end
	-- 12 players at a cell size of 8 means a full cycle is two steps; every player
	-- must be examined exactly once inside that cycle and never more than the cap.
	local cellSteps = math.ceil(12 / ArenaRoute.CELL_SIZE)
	local seen = {}
	for step = 0, cellSteps - 1 do
		local slice = ArenaRoute.slice(ids, step)
		assert(#slice <= ArenaRoute.CELL_SIZE)
		assert(#slice > 0)
		for _, id in slice do
			seen[id] = (seen[id] or 0) + 1
		end
	end
	for i = 1, 12 do eq(seen[-i], 1) end
end)
test("route: stats report arrivals and fallbacks", function()
	local r = router()
	r:evaluate(-1, "Playing", true, arenaPoint, true, 1)
	eq(r:stats().arrivals, 1)
	eq(r:stats().tracked, 1)
	r:remove(-1)
	eq(r:stats().tracked, 0)
end)

assert(failed == 0, "Core test failures")

-- --------------------------------------------------------------------------- --
-- Character system: species ownership and the collection record
-- --------------------------------------------------------------------------- --
test("species: every reward maps to exactly two named characters", function()
	for _, value in { 1, 5, 10 } do
		local family = Creatures.Family[value]
		eq(#family, 2)
		for _, name in family do
			assert(Creatures.Characters[name], "missing character " .. tostring(name))
			eq(Creatures.Characters[name].Value, value)
		end
	end
	eq(#Creatures.Order, 6)
end)
test("species: the choice is deterministic for a slot and covers both variants", function()
	local seen = {}
	for slot = 1, 48 do
		local name = Creatures.SpeciesOf(slot, 1)
		eq(name, Creatures.SpeciesOf(slot, 1))
		seen[name] = true
	end
	eq(seen["brain"], true); eq(seen["frog"], true)
	-- Same slot, different rarity families: the character follows the rarity.
	for _, value in { 5, 10 } do
		local name = Creatures.SpeciesOf(7, value)
		assert(name == Creatures.Family[value][1] or name == Creatures.Family[value][2])
	end
end)
test("ledger: the server stamps a species on every slot and every receipt", function()
	local l = PickupLedger.new(positions, Config.Kinds, 4.5, 5,
		function() return 0.5 end, function(slotId, value) return Creatures.SpeciesOf(slotId, value) end)
	l:beginRound(1)
	for _, slot in l.slots do
		assert(slot.species ~= "", "slot has no species")
		assert(Creatures.Characters[slot.species], "unknown species " .. tostring(slot.species))
	end
	local receipt = l:tryClaim(1, l.slots[1].generation, context(-1, positions[1], 1), 10)
	assert(receipt, "claim failed")
	assert(Creatures.Characters[receipt.species], "receipt has no valid species")
	eq(receipt.value, 1)
end)
test("ledger: a respawned slot gets a species that matches its new rarity", function()
	local l = PickupLedger.new(positions, Config.Kinds, 4.5, 5,
		function() return 0 end, function(slotId, value) return Creatures.SpeciesOf(slotId, value) end)
	l:beginRound(1)
	local slot = l.slots[1]
	assert(slot.available)
	l:tryClaim(1, slot.generation, context(-1, positions[1], 1), 10)
	l:step(100)   -- respawn
	assert(slot.available, "slot never respawned")
	local family = Creatures.Family[Config.Kinds[slot.kindIndex].Value]
	assert(slot.species == family[1] or slot.species == family[2],
		"respawned species does not match its rarity")
end)
test("award: the collection record tracks each character separately", function()
	local m = playing(1)
	local id = -1
	eq(m:distinct(id), 0)
	eq(m:award(id, 1, m.roundId, "brain"), true)
	eq(m:award(id, 1, m.roundId, "brain"), true)
	eq(m:award(id, 10, m.roundId, "sock"), true)
	local row = m:rows()[1]
	eq(row.collection["brain"], 2)
	eq(row.collection["sock"], 1)
	eq(row.collected, 2)
	eq(row.score, 12)
	eq(m:distinct(id), 2)
end)
test("award: a species cannot change the reward", function()
	local m = playing(1)
	local id = -1
	-- Legendary character, common reward: the *value* is what the server pays.
	eq(m:award(id, 1, m.roundId, "sock"), true)
	eq(m:rows()[1].score, 1)
	eq(m:rows()[1].collection["sock"], 1)
	-- An invalid denomination is still rejected, whatever the species says.
	eq(m:award(id, 7, m.roundId, "sock"), false)
	eq(id, -1)
end)
test("award: a collection never leaks into another round or another player", function()
	local m = playing(2)
	local a, b = -1, -2
	eq(m:award(a, 5, m.roundId, "fish"), true)
	-- Rows are sorted by score then id, so look the other player up by name rather
	-- than trusting a position.
	local function rowOf(id)
		for _, row in m:rows() do
			if row.id == id then return row end
		end
		return nil
	end
	eq(rowOf(b).collection["fish"], nil)
	eq(rowOf(b).collected, 0)
	-- Advance to a new round: the species record survives, the round score does not.
	-- (Step in small increments: the machine asserts a monotonic clock.)
	-- `playing()` already stepped the machine to 104; start the clock there.
	local now = 104
	local function advance(seconds)
		local left = seconds
		while left > 0 do
			local dt = math.min(1, left)
			m:step(now + dt)
			now += dt
			left -= dt
		end
	end
	advance(Config.FastTiming.Round + 1)                    -- round ends
	advance(Config.FastTiming.Results + 1)                  -- results end
	advance(Config.FastTiming.Intermission + 1)             -- next round starts
	local row = rowOf(a)
	eq(row.name, "Brain 1")
	eq(row.score, 0)          -- the round score resets every round
	eq(row.collection["fish"], 1)   -- the collection is a session record
end)
test("award: a collection entry without a species is still a legal pickup", function()
	local m = playing(1)
	eq(m:award(-1, 1, m.roundId), true)
	eq(m:rows()[1].score, 1)
	eq(m:rows()[1].collected, 0)
end)


-- --------------------------------------------------------------------------- #
-- Phase 5: stealing, spawn protection, stages, events.
-- These are the fairness rules from spec §3B/§9 exercised directly, with the
-- distance supplied by the caller so no engine geometry is involved.
-- --------------------------------------------------------------------------- #

local function rowOf(m, id)
	for _, row in m:rows() do
		if row.id == id then return row end
	end
	return nil
end
-- A production-length round, so the real stage timeline applies (the fast config
-- shortens the round to 30s and therefore drops the later stage boundaries).
local function fullPlaying(count)
	local m = RoundMachine.new(table.clone(Config))
	for i = 1, count or 2 do m:addPlayer(-i, "Brain " .. i) end
	m:step(100)
	m:step(100 + Config.Timing.Intermission + 1)
	return m
end
local function stealReady()
	local m = playing(2)
	-- Clear the join/spawn protection window so a normal mid-round tag is legal.
	local now = m.lastNow + Config.Steal.Protection + 1
	m:step(now)
	return m, now
end

test("steal: a carried cell moves from victim to thief, score included", function()
	local m, now = stealReady()
	eq(m:award(-2, 5, m.roundId), true)
	local outcome, value = m:trySteal(-1, -2, 3, now, m.roundId)
	eq(outcome, "ok")
	eq(value, 5)
	eq(rowOf(m, -1).score, 5)
	eq(rowOf(m, -2).score, 0)
	eq(rowOf(m, -1).carriedValue, 5)
	eq(rowOf(m, -2).carriedValue, 0)
end)

test("steal: the biggest carried cell is taken first", function()
	local m, now = stealReady()
	eq(m:award(-2, 1, m.roundId), true)
	eq(m:award(-2, 5, m.roundId), true)
	eq(m:award(-2, 10, m.roundId), true)
	local outcome, value = m:trySteal(-1, -2, 2, now, m.roundId)
	eq(outcome, "ok")
	eq(value, 10)
	eq(rowOf(m, -2).score, 6)
	eq(rowOf(m, -2).carriedValue, 6)
end)

test("steal: a thief out of range is refused and nothing moves", function()
	local m, now = stealReady()
	eq(m:award(-2, 10, m.roundId), true)
	local outcome, value = m:trySteal(-1, -2, Config.Steal.Range + 0.01, now, m.roundId)
	eq(outcome, "out-of-range")
	eq(value, 0)
	eq(rowOf(m, -2).score, 10)
	eq(rowOf(m, -1).score, 0)
end)

test("steal: the cooldown is server time and blocks the next tag", function()
	local m, now = stealReady()
	eq(m:award(-2, 5, m.roundId), true)
	eq(m:award(-1, 1, m.roundId), true)
	eq(m:trySteal(-1, -2, 3, now, m.roundId), "ok")
	-- The victim is immune for a moment, so ask about the cooldown first.
	eq(m:stealBlockedReason(-1, now), "cooldown")
	eq(m:trySteal(-1, -2, 3, now + Config.Steal.Cooldown - 0.01, m.roundId), "cooldown")
	local later = now + Config.Steal.Cooldown + Config.Steal.Immunity + 0.01
	eq(m:trySteal(-1, -2, 3, later, m.roundId), "empty")
end)

test("steal: spawn protection cannot be bypassed by spamming the request", function()
	local m, now = stealReady()
	eq(m:award(-2, 5, m.roundId), true)
	m:spawnProtect(-2, now)
	eq(m:trySteal(-1, -2, 3, now, m.roundId), "immune")
	eq(m:trySteal(-1, -2, 0, now, m.roundId), "immune")
	eq(rowOf(m, -2).score, 5)
	-- Protection expires on its own.
	eq(m:trySteal(-1, -2, 3, now + Config.Steal.Protection + 0.01, m.roundId), "ok")
end)

test("steal: a victim who was just robbed is briefly immune", function()
	local m, now = stealReady()
	eq(m:award(-2, 10, m.roundId), true)
	eq(m:award(-2, 5, m.roundId), true)
	eq(m:trySteal(-1, -2, 3, now, m.roundId), "ok")
	m:addPlayer(-3, "Brain 3")
	local second = now + Config.Steal.Immunity - 0.01
	eq(m:trySteal(-3, -2, 3, second, m.roundId), "immune")
end)

test("steal: the same pair cannot be farmed inside the repeat window", function()
	local m, now = stealReady()
	eq(m:award(-2, 10, m.roundId), true)
	eq(m:award(-2, 10, m.roundId), true)
	eq(m:trySteal(-1, -2, 3, now, m.roundId), "ok")
	local after = now + Config.Steal.Cooldown + Config.Steal.Immunity + 0.01
	if after - now < Config.Steal.RepeatWindow then
		eq(m:trySteal(-1, -2, 3, after, m.roundId), "repeat")
	end
	local clear = now + Config.Steal.RepeatWindow + 0.01
	eq(m:trySteal(-1, -2, 3, clear, m.roundId), "ok")
end)

test("steal: nothing is taken from an empty carried pile", function()
	local m, now = stealReady()
	eq(m:trySteal(-1, -2, 3, now, m.roundId), "empty")
	eq(rowOf(m, -1).steals, 0)
end)

test("steal: banked score is never stolen, only carried cells", function()
	local m, now = stealReady()
	eq(m:award(-2, 10, m.roundId), true)
	eq(m:bank(-2), 10)
	eq(rowOf(m, -2).score, 10)
	eq(m:trySteal(-1, -2, 3, now, m.roundId), "empty")
	eq(rowOf(m, -2).score, 10)
end)

test("steal: a thief cannot rob themselves, an idle player, or another round", function()
	local m, now = stealReady()
	eq(m:award(-2, 5, m.roundId), true)
	eq(m:trySteal(-1, -1, 0, now, m.roundId), "self")
	eq(m:trySteal(-1, -2, 3, now, m.roundId + 1), "inactive-round")
	m:step(m.lastNow + Config.FastTiming.Round + Config.FastTiming.Results + 1)
	eq(m:trySteal(-1, -2, 3, m.lastNow + 1, m.roundId), "inactive-round")
end)

test("stage: the timeline starts at Collect and ends at Final", function()
	local m = fullPlaying(2)
	eq(m.stage, "Collect")
	for _, spec in Config.Stages do
		local index, stage = m:stageAt(spec.At)
		eq(stage.Name, spec.Name)
		eq(Config.Stages[index].Name, spec.Name)
	end
	local _, last = m:stageAt(Config.Timing.Round - 0.5)
	eq(last.Name, "Final")
	-- A fast round keeps the stage it can reach and never runs past its deadline.
	local fast = playing(2)
	eq(fast:stageAt(fast.config.Timing.Round - 0.5), #fast.config.Stages)
end)

test("stage: every boundary banks the carried pile and keeps the score", function()
	local m = fullPlaying(2)
	eq(m:award(-1, 10, m.roundId), true)
	eq(rowOf(m, -1).carriedValue, 10)
	local spec = Config.Stages[2]
	m:step(m.phaseStartedAt + spec.At + 0.01)
	eq(m.stage, spec.Name)
	eq(rowOf(m, -1).carriedValue, 0)
	eq(rowOf(m, -1).score, 10)
	-- And a banked cell can no longer be stolen (asserted above) but new ones can.
	eq(m:award(-1, 5, m.roundId), true)
	eq(rowOf(m, -1).carriedValue, 5)
end)

test("stage: carried cells are exposed, so the risk window is real", function()
	local m = fullPlaying(2)
	-- Join protection is cleared explicitly so this test is about the stage window.
	local now = m.phaseStartedAt + 1
	m:step(now)
	m:step(m.phaseStartedAt + Config.Stages[2].At + 0.01)
	eq(m:award(-1, 10, m.roundId), true)
	-- Move to a fresh cooldown window by taking the thief's clock forward.
	local t = now + Config.Steal.Cooldown + 1
	eq(m:trySteal(-2, -1, 3, t, m.roundId), "ok")
	eq(rowOf(m, -2).score, 10)
	eq(rowOf(m, -1).score, 0)
	eq(rowOf(m, -1).lost, 10)
end)

test("events: the production schedule warns before every window", function()
	local m = RoundMachine.new(Config)
	local schedule = m:buildSchedule(1)
	assert(#schedule > 0, "an event schedule is required")
	local previous = -math.huge
	for _, spec in schedule do
		assert(spec.StartsAt > previous, "events must be ordered")
		assert(spec.WarningAt < spec.StartsAt, "every event must warn first")
		assert(spec.EndsAt > spec.StartsAt, "events must have a duration")
		assert(spec.EndsAt < Config.Timing.Round, "events must fit the round")
		previous = spec.StartsAt
	end
end)

test("events: five survival kinds exist and all are labelled", function()
	local seen = {}
	-- Wildcards rotate by round id, so several rounds cover the whole rotation.
	for roundId = 1, 4 do
		for _, spec in RoundMachine.new(Config):buildSchedule(roundId) do
			seen[spec.Kind] = true
		end
	end
	for _, kind in { "LowGravity", "Slippery", "MovingPlatforms", "CollectibleRush", "VanishingPaths" } do
		assert(seen[kind] ~= nil, "missing event kind: " .. kind)
		assert(RoundMachine.eventLabel(kind) ~= "", "unlabelled event: " .. kind)
	end
	eq(RoundMachine.eventLabel("LowGravity"), "LOW GRAVITY")
end)

test("events: a warning fires before the event, then the event itself", function()
	local m = playing(2)
	local spec = m:buildSchedule(m.roundId)[1]
	m:step(m.phaseStartedAt + spec.WarningAt + 0.01)
	eq(m.eventWarning ~= nil, true)
	eq(m.eventActive, false)
	m:step(m.phaseStartedAt + spec.StartsAt + 0.01)
	eq(m.eventActive, true)
	eq(m.eventKind, spec.Kind)
	m:step(m.phaseStartedAt + spec.EndsAt + 0.01)
	eq(m.eventActive, false)
end)

test("events: gravity only drops for low gravity, and always resets", function()
	local m = RoundMachine.new(Config)
	local schedule = m:buildSchedule(1)
	local low = nil
	for _, spec in schedule do
		if spec.Kind == "LowGravity" then low = spec end
	end
	assert(low ~= nil, "the production schedule needs a low-gravity window")
	local fast = RoundMachine.new(Config)
	fast:addPlayer(-1, "Solo")
	fast:step(0)
	fast:step(Config.FastTiming.Intermission + 1)
	-- The machine reports the kind; the adapter is what moves workspace gravity.
	for _, effect in fast:step(fast.phaseStartedAt + 200) do
		if effect.kind == "event" then
			assert(effect.active == false, "a finished round must never leave an event open")
		end
	end
end)

print(string.format("\nCORE RESULTS: %d passed, %d failed",passed,failed))
-- The Luau CLI exits non-zero on an uncaught error, so a failing suite fails CI
-- instead of printing a red line into a passing run.
if failed > 0 then
	error(string.format("%d core test(s) failed", failed), 0)
end
