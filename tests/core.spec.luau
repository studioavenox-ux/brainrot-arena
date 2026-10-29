--!nonstrict
-- Executed by the official Luau CLI, not a JavaScript/Python translation.
local RoundMachine = require("../src/server/core/RoundMachine")
local PickupLedger = require("../src/server/core/PickupLedger")
local MovementGuard = require("../src/server/core/MovementGuard")
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

print(string.format("\nCORE RESULTS: %d passed, %d failed",passed,failed))
assert(failed == 0, "Core test failures")
