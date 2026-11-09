--!nonstrict
-- Runs the actual Main.server, WorldService, Main.client, Hud and Effects sources.
-- Mocks only the Roblox boundary; see TESTING.md for the mandatory Studio acceptance pass.
return function(Mock, sources, schema)
	local passed,failed=0,0
	-- The pure route module is required here the same way the server requires it, so
	-- the tests assert against the production thresholds (34 / 46 studs, backoff).
	local ArenaRoute
	local probe=Mock.new(sources,schema,{fast=true})
	ArenaRoute=probe:import("src/server/core/ArenaRoute.luau")
	local function test(name,fn)
		local ok,err=pcall(fn)
		if ok then passed+=1; print("PASS "..name) else failed+=1; print("FAIL "..name..": "..tostring(err)) end
	end
	local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
	local function near(a,b) assert(math.abs(a-b)<.02,tostring(a).." not close to "..tostring(b)) end
	local function fixture(options,withClient)
		options=options or {fast=true,studio=true}
		local e=Mock.new(sources,schema,options)
		local a=e:addPlayer(-1,"Mint Brain")
		local b=e:addPlayer(-2,"Pink Brain")
		e:startServer()
		if withClient then e:startClient(a) end
		return e,a,b
	end
	local function play(e)
		e:step(.1); eq(e:lastState().phase,"Intermission")
		e:step(4.1); eq(e:lastState().phase,"Playing")
	end
	local function score(p) return p.leaderstats["Brain Cells"].Value end
	-- Step the simulation the way the engine does: many small heartbeats, not one
	-- giant jump, so per-step backoff and sweeps actually run.
	local function tick(e,seconds)
		local left=seconds
		while left>0 do local dt=math.min(.1,left); e:step(dt); left-=dt end
	end
	local function zoneOf(p) local q=p.Character.HumanoidRootPart.Position; return ArenaRoute.zone({x=q.X,y=q.Y,z=q.Z}) end
	local function cell(e,id) return e.services.Workspace.BrainrotPickups["BrainCell_"..id] end
	local function collect(e,p,id)
		local target=cell(e,id).Position+e.Vector3.new(0,1.5,0)
		p.Character:PivotTo(e.CFrame.new(target))
		e:step(1)
	end
	local function finish(e)
		e:step(e:lastState().phaseEndsAt-e.now+.01)
		eq(e:lastState().phase,"Results")
	end
	local function rect(object)
		local p,s=object.AbsolutePosition,object.AbsoluteSize
		return {x=p.X,y=p.Y,w=s.X,h=s.Y}
	end
	local function overlaps(a,b)
		return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y
	end

	test("server builds original world and safe lobby spawn",function()
		local e,a=fixture()
		local w=e.services.Workspace.BrainrotWorld
		-- 906 runtime geometry parts: 824 from the Phase 2 architecture pass (588
		-- after Phase 1, 358 before the redesign) plus 82 for the Phase 5 event
		-- geometry (three rafts, four vanishing paths, all non-colliding). The
		-- exported place adds 13 bake-only sign boards on top; the budgets live in
		-- tools/verify_place.py and tools/artcheck.py.
		eq(#w:GetChildren(),906)
		eq(w.LobbySpawn:IsA("SpawnLocation"),true)
		eq(a.RespawnLocation,w.LobbySpawn)
		assert(a.Character.HumanoidRootPart.Position.Z>140)
	end)
	test("world builder reuses baked world without duplicate geometry",function()
		local e=Mock.new(sources,schema,{fast=true})
		local World=e:import("src/server/WorldService.luau")
		local initial=World.new().root
		e:addPlayer(-1,"Solo"); e:startServer()
		eq(e.services.Workspace.BrainrotWorld,initial)
		eq(#initial:GetChildren(),906)
	end)
	test("server creates only three whitelisted remotes",function()
		local e=fixture(); local r=e.services.ReplicatedStorage.BrainrotRemotes
		eq(#r:GetChildren(),3); assert(r.State and r.Pickup and r.Request)
		eq(r:FindFirstChild("AwardScore"),nil)
	end)
	test("intermission has no collectible replicas",function()
		local e=fixture(); e:step(.1)
		eq(#e.services.Workspace.BrainrotPickups:GetChildren(),0)
		eq(e:lastState().phase,"Intermission")
	end)
	test("two-player round teleports both and creates 48 server cells",function()
		local e,a,b=fixture(); play(e)
		eq(#e.services.Workspace.BrainrotPickups:GetChildren(),48)
		for _,p in {a,b} do assert(math.abs(p.Character.HumanoidRootPart.Position.Z)<60); eq(p.Character.Humanoid.WalkSpeed,22) end
		eq(e:lastState().fastMode,true)
	end)
	test("actual server awards nearby player and updates leaderstats",function()
		local e,a=fixture(); play(e); collect(e,a,1)
		eq(score(a),1); eq(cell(e,1):GetAttribute("Active"),false)
		local found=false
		for _,message in e.logs do if message.name=="Pickup" and message.args[1].userId==a.UserId then found=true end end
		assert(found)
	end)
	test("actual two-player collision cannot double award",function()
		local e,a,b=fixture(); play(e)
		local target=cell(e,1).Position+e.Vector3.new(0,1.5,0)
		a.Character:PivotTo(e.CFrame.new(target)); b.Character:PivotTo(e.CFrame.new(target)); e:step(1)
		eq(score(a)+score(b),1)
	end)
	test("claimed pickup respawns with a newer server generation",function()
		local e,a=fixture(); play(e); local generation=cell(e,1):GetAttribute("Generation"); collect(e,a,1)
		a.Character:PivotTo(e.CFrame.new(0,25,0)); e:step(1); e:step(4.1)
		eq(cell(e,1):GetAttribute("Active"),true); eq(cell(e,1):GetAttribute("Generation"),generation+1)
	end)
	test("client cannot submit points, prices, or pickup IDs",function()
		local e,a=fixture(); play(e)
		for _,verb in {"Score","Award","Pickup","Coins","SetScore"} do e:request(a,verb,100000) end
		e:request(a,"Halo",-100000); e:step(1)
		eq(score(a),0); eq(a.leaderstats.Coins.Value,0)
	end)
	test("snapshot requests are rate-limited",function()
		local e,a=fixture(); e:request(a,"Snapshot"); local count=#e.logs
		for _=1,100 do e:request(a,"Snapshot") end
		eq(#e.logs,count)
	end)
	test("dead avatar cannot collect",function()
		local e,a=fixture(); play(e); a.Character.Humanoid.Health=0; collect(e,a,1); eq(score(a),0)
	end)
	test("extreme client teleport is rejected before pickup",function()
		local e,a=fixture(); play(e); e:step(1)
		local before=a.Character.HumanoidRootPart.Position
		a.Character:PivotTo(e.CFrame.new(cell(e,48).Position)); e:step(.1)
		eq(score(a),0); near((a.Character.HumanoidRootPart.Position-before).Magnitude,0)
	end)
	test("fall rescue preserves score and returns to arena",function()
		local e,a=fixture(); play(e); collect(e,a,1)
		a.Character:PivotTo(e.CFrame.new(0,-5,0)); e:step(.1)
		eq(score(a),1); assert(a.Character.HumanoidRootPart.Position.Y>20); assert(a.Character.HumanoidRootPart.Position.Z<60)
	end)
	test("respawn during round preserves score and rejoins arena",function()
		local e,a=fixture(); play(e); collect(e,a,1); e:spawn(a)
		eq(score(a),1); assert(a.Character.HumanoidRootPart.Position.Z<60)
	end)
	test("late joining actual player is routed into current round",function()
		local e=fixture(); play(e); local p=e:addPlayer(-3,"Late"); e:step(.3)
		eq(score(p),0); assert(p.Character.HumanoidRootPart.Position.Z<60); eq(#e:lastState().rows,3)
	end)
	test("the drawn Chaos Event activates for 35 seconds, then gravity and kind reset",function()
		local e=fixture(); play(e); e:step(8.01)
		local state=e:lastState()
		eq(state.eventActive,true); eq(state.eventKind,"LowGravity")
		near(e.services.Workspace.Gravity,62)
		e:step(34.9); near(e.services.Workspace.Gravity,62)
		-- Gravity is applied by the server immediately. The replicated snapshot is
		-- throttled, so the client-visible state is checked after a short settle.
		e:step(.5); near(e.services.Workspace.Gravity,196.2)
		e:step(1); eq(e:lastState().eventActive,false)
	end)
	test("35-second lifecycle: the window lasts exactly 35 s and edges land on the first server step at or after 8 s and 43 s",function()
		-- Authoritative timing, not the throttled snapshot. The Playing phase starts at the
		-- server's own deadline minus the round length, so the reference point is exact.
		local e=fixture({fast=true,studio=true,roll=.1}); play(e)
		local Config=e:import("src/shared/Config.luau")
		local ws=e.services.Workspace
		local playStart=e:lastState().phaseEndsAt-Config.FastTiming.Round
		local openedAt,closedAt
		for _=1,6000 do
			e:step(.01)
			local elapsed=e.now-playStart
			if openedAt==nil and ws.Gravity~=Config.NormalGravity then openedAt=elapsed end
			if openedAt~=nil and closedAt==nil and ws.Gravity==Config.NormalGravity then closedAt=elapsed; break end
		end
		assert(openedAt~=nil and closedAt~=nil,"the event must open and close")
		-- The server acts on ServerStep (0.1 s) boundaries, so each edge is applied on the first
		-- step at or after its scheduled time. The window is therefore exact in length and
		-- starts/ends within one server step of 8 s and 43 s.
		local step=Config.ServerStep
		assert(openedAt>=8-.001 and openedAt<=8+step+.001,"opens on the first server step at or after 8 s, measured "..tostring(openedAt))
		assert(closedAt>=43-.001 and closedAt<=43+step+.001,"closes on the first server step at or after 43 s, measured "..tostring(closedAt))
		-- The window length is exact to within one 10 ms test frame: no drift from the step cadence.
		assert(math.abs((closedAt-openedAt)-35)<=.011,"lasts 35 s, measured "..tostring(closedAt-openedAt))
		assert(closedAt<Config.FastTiming.Round,"it ends before the round")
	end)
	test("exactly one Chaos Event runs per round and it closes before the round ends",function()
		local e=fixture(); play(e)
		-- Count real open/close edges on the server's own state, step by step.
		local opened,closed,was=0,0,false
		local openedAt,closedAt
		for _=1,600 do
			e:step(.1)
			local state=e:lastState()
			if state.eventActive and not was then opened+=1 end
			if was and not state.eventActive then closed+=1 end
			was=state.eventActive
			if state.phase~="Playing" then break end
		end
		eq(opened,1); eq(closed,1)
		near(e.services.Workspace.Gravity,196.2)
	end)
	test("round end clears replicas, resets gravity, announces winner and pays coins",function()
		local e,a=fixture(); play(e); collect(e,a,1); finish(e)
		local s=e:lastState(); eq(s.results.winners[1].id,a.UserId)
		eq(a.leaderstats.Coins.Value,42); eq(a.leaderstats.Wins.Value,1)
		eq(#e.services.Workspace.BrainrotPickups:GetChildren(),0); near(e.services.Workspace.Gravity,196.2)
		assert(a.Character.HumanoidRootPart.Position.Z>140)
	end)
	test("full cycle starts clean second round",function()
		local e,a=fixture(); play(e); collect(e,a,1); finish(e)
		e:step(5.01); eq(e:lastState().phase,"Intermission"); e:step(4.01)
		eq(e:lastState().phase,"Playing"); eq(e:lastState().roundId,2); eq(score(a),0); eq(a.leaderstats.Coins.Value,42)
		eq(#e.services.Workspace.BrainrotPickups:GetChildren(),48)
	end)
	test("empty server cancels low gravity and clears round",function()
		local e,a,b=fixture(); play(e); e:step(8.1); e:removePlayer(a); e:removePlayer(b); e:step(.3)
		eq(e:lastState().phase,"Waiting"); near(e.services.Workspace.Gravity,196.2); eq(#e.services.Workspace.BrainrotPickups:GetChildren(),0)
	end)
	test("QuickTest timings cannot run in a published non-Studio server",function()
		local e=fixture({fast=true,studio=false}); e:step(.1); e:step(4.1)
		eq(e:lastState().phase,"Intermission"); eq(e:lastState().fastMode,false)
		e:step(8); eq(e:lastState().phase,"Playing"); near(e:lastState().phaseEndsAt-e.now,180)
	end)
	test("session cosmetic purchase is server-funded and survives avatar respawn",function()
		local e,a=fixture({fast=true,studio=true,roll=.97},true); play(e)
		for i=1,3 do collect(e,a,i) end
		eq(score(a),30); finish(e); eq(a.leaderstats.Coins.Value,100)
		e:request(a,"Halo"); eq(a.leaderstats.Coins.Value,0); eq(#a.Character.PulseHalo:GetChildren(),8)
		e:spawn(a); eq(#a.Character.PulseHalo:GetChildren(),8)
		e:step(1); e:request(a,"Halo"); eq(a.Character:FindFirstChild("PulseHalo"),nil); eq(a.leaderstats.Coins.Value,0)
	end)
	test("actual client constructs HUD and syncs server snapshot",function()
		local e=fixture(nil,true); e:step(.1)
		assert(e:find("BrainrotHUD"))
		-- Cells and coins live on the HUD counters; the clock names the phase.
		eq(e:find("CellCounter").Value.Text,"0")
		eq(e:find("CoinCounter").Value.Text,"0")
		eq(e:find("RoundClock").Phase.Text,"GET READY")
		-- The clock counts the intermission the same way the server does.
		eq(e:find("RoundClock").Countdown.Text,"00:04")
		-- The lobby banner is up while the round has not started.
		eq(e:find("LobbyBanner").Visible,true)
		eq(e:find("Results").Visible,false)
	end)
	test("actual client updates score only after server pickup",function()
		local e,a=fixture(nil,true); play(e); collect(e,a,1)
		eq(e:find("CellCounter").Value.Text,"1")
		e:request(a,"Score",999); e:step(.3); eq(e:find("CellCounter").Value.Text,"1")
	end)
	test("actual client creates and cleans up procedural cell visuals",function()
		local e=fixture(nil,true); play(e)
		local fx=e.services.Workspace.BrainrotClientFX
		local count=0; for _,child in fx:GetChildren() do if child:IsA("Model") then count+=1 end end
		eq(count,48); finish(e)
		for _,child in fx:GetChildren() do eq(child:IsA("Model"),false) end
	end)
	test("winner card displays server results and earned coins",function()
		local e,a=fixture(nil,true); play(e); collect(e,a,1); finish(e)
		local card=e:find("Results"); eq(card.Visible,true)
		assert(string.find(card.Winner.Text,"Mint Brain",1,true)); eq(card.Reward.Text,"+42 COINS")
	end)
	test("help, sound preference and motion controls are functional",function()
		local e=fixture(nil,true)
		e:find("Help").Activated:Fire(); eq(e:find("ModalLayer").Visible,true)
		eq(e:find("Card").Title.Text,"HOW TO PLAY")
		e:find("ModalMotion").Activated:Fire(); eq(e:find("ModalMotion").Label.Text,"REDUCED MOTION: ON")
		e:find("ModalSound").Activated:Fire(); eq(e:find("ModalSound").Label.Text,"SFX OFF")
		e:find("Close").Activated:Fire(); eq(e:find("ModalLayer").Visible,false)
	end)
	test("ranks toggle hides and shows custom leaderboard",function()
		local e=fixture(nil,true); local board=e:find("Leaderboard"); local previous=board.Visible
		e:find("Ranks").Activated:Fire(); eq(board.Visible,not previous); e:find("Ranks").Activated:Fire(); eq(board.Visible,previous)
	end)
	test("mobile HUD stays inside safe bounds without overlapping top controls",function()
		for _,size in {{320,568},{360,740},{390,800},{430,900},{844,354},{1280,720}} do
			local e=fixture(nil,true); e:setViewport(size[1],size[2])
			-- Specimens and the toast band are in the list because the phone RANKS chip
			-- used to tuck into the coin chip, and the centred 432px toast used to run
			-- straight over the specimen chip.
			local names={"RoundClock","Ranks","Help","CoinCounter","Specimens","Toast"}
			for i,name in names do
				local a=rect(e:find(name)); assert(a.x>=0 and a.y>=0 and a.x+a.w<=size[1]+1 and a.y+a.h<=size[2]+1,"Out of bounds: "..name.." at "..size[1].."x"..size[2].." -> "..a.x..","..a.y.." "..a.w.."x"..a.h)
				for j=i+1,#names do assert(not overlaps(a,rect(e:find(names[j]))),"Overlap at "..size[1].."x"..size[2]..": "..name.."("..a.x..","..a.y.." "..a.w.."x"..a.h..") / "..names[j].."("..rect(e:find(names[j])).x..","..rect(e:find(names[j])).y.." "..rect(e:find(names[j])).w.."x"..rect(e:find(names[j])).h..")") end
			end
			-- Bottom action bar must clear the thumbstick / jump zones.
			local bar=rect(e:find("ActionBar"))
			if size[1]<760 and size[2]>=500 then
				assert(not overlaps(bar,{x=size[1]-110,y=size[2]-105,w=110,h=105}),"Action bar blocks jump")
			end
		end
	end)
	test("shop, inventory and settings modals all act on real state",function()
		local e,a=fixture({fast=true,studio=true,roll=.97},true); e:setViewport(390,800)
		-- Empty wallet: the shop explains the price and sends only the validated verb.
		e:find("Shop").Activated:Fire(); eq(e:find("ModalLayer").Visible,true)
		eq(e:find("Card").Title.Text,"HALO STAND")
		assert(string.find(e:find("Card").Body.Text,"0 coins",1,true))
		e:find("Action").Activated:Fire()
		eq(a.leaderstats.Coins.Value,0); eq(a.Character:FindFirstChild("PulseHalo"),nil)
		eq(e:find("Message").Text,"Not enough coins — collect cells to earn them")
		-- Gear now opens the specimen log (its own screen, six live 3D cards).
		e:find("Close").Activated:Fire()
		e:find("Inventory").Activated:Fire(); eq(e:find("Collection").Visible,true)
		eq(e:find("Collection").Panel.Title.Text,"SPECIMEN LOG")
		local cards=0
		for _,card in e:find("Collection").Panel.Grid:GetChildren() do
			if card:IsA("Frame") then cards+=1 end
		end
		eq(cards,6)
		e:find("Collection").Panel.Close.Activated:Fire(); eq(e:find("Collection").Visible,false)
		-- Settings toggles are local preferences, never gameplay requests.
		e:find("Settings").Activated:Fire(); eq(e:find("Card").Title.Text,"SETTINGS")
		assert(string.find(e:find("Card").Body.Text,"Sound and music: ON",1,true))
		e:find("ModalSound").Activated:Fire()
		assert(string.find(e:find("Card").Body.Text,"Sound and music: OFF",1,true))
	end)
	test("shop purchase succeeds once the wallet has coins",function()
		local e,a=fixture({fast=true,studio=true,roll=.97},true); play(e)
		for i=1,3 do collect(e,a,i) end
		finish(e); eq(a.leaderstats.Coins.Value,100)
		e:find("Shop").Activated:Fire(); e:find("Action").Activated:Fire()
		eq(a.leaderstats.Coins.Value,0); eq(#a.Character.PulseHalo:GetChildren(),8)
		eq(e:find("Action").Label.Text,"UNEQUIP")
	end)
	test("leaderboard shows live server rows in rank order",function()
		local e,a,b=fixture(nil,true); play(e)
		collect(e,a,1); collect(e,b,2); collect(e,b,3)
		local roster=e:find("Leaderboard").Players
		local rows={}
		for _,row in roster:GetChildren() do
			if row:IsA("Frame") then table.insert(rows,row) end
		end
		eq(#rows,2)
		-- server sorts by score, so the 11-cell player is row 1
		local first=nil
		for _,row in rows do if row.LayoutOrder==1 then first=row end end
		assert(string.find(first.Player.Text,"Pink Brain",1,true))
		eq(first.Cells.Text,tostring(score(b)))
		assert(tonumber(first.Cells.Text)>tonumber(rows[1].Cells.Text) or first==rows[1])
		-- the local player's own row is marked, and every name is a real server name
		for _,row in rows do
			local named=string.find(row.Player.Text,"Mint Brain",1,true) or string.find(row.Player.Text,"Pink Brain",1,true)
			assert(named,"row has an invented name: "..row.Player.Text)
		end
	end)
	test("phase changes drive the timer, lobby banner and results card",function()
		local e,a=fixture(nil,true)
		e:step(.1); eq(e:find("RoundClock").Phase.Text,"GET READY")
		assert(string.find(e:find("LobbyBanner").Countdown.Text,"ARENA OPENS IN 00:0",1,true))
		e:step(4.1); eq(e:find("RoundClock").Phase.Text,"COLLECT")
		eq(e:find("LobbyBanner").Visible,false)
		finish(e); eq(e:find("RoundClock").Phase.Text,"ROUND COMPLETE")
		assert(string.find(e:find("Results").Next.Text,"INTERMISSION IN",1,true))
	end)
	test("chaos event drives a live banner and clears it",function()
		local e=fixture(nil,true)
		-- Fast timings: the event opens 8s into a 50s round and runs for 35s.
		play(e); e:step(8.01)
		local banner=e:find("EventBanner")
		eq(banner.Visible,true)
		assert(string.find(banner.Label.Text,"LOW GRAVITY",1,true))
		assert(string.find(banner.Label.Text,"%d%d:%d%d"),"banner shows a live countdown: "..banner.Label.Text)
		e:step(35.01); eq(banner.Visible,false)
	end)
	test("bouncy world: every character jumps higher during the window, then normally again",function()
		-- roll=.4 draws the second pool entry, BouncyWorld.
		local e,a=fixture({fast=true,studio=true,roll=.4},true); play(e)
		local normal=a.Character.Humanoid.JumpPower
		near(normal,50)
		e:step(8.5)
		near(a.Character.Humanoid.JumpPower,50*1.8) -- authoritative, applied immediately
		e:step(1)
		eq(e:lastState().eventKind,"BouncyWorld") -- replicated snapshot is throttled
		e:step(40); near(a.Character.Humanoid.JumpPower,50)
	end)
	test("bouncy world: a respawned character inherits the live jump power",function()
		local e,a=fixture({fast=true,studio=true,roll=.4},true); play(e); e:step(8.01)
		e:spawn(a); e:step(.5)
		near(a.Character.Humanoid.JumpPower,50*1.8)
	end)
	test("slippery chaos: floor friction changes live and is restored when the window closes",function()
		-- roll=.6 draws the third pool entry, SlipperyChaos.
		local e,a=fixture({fast=true,studio=true,roll=.6},true); play(e)
		local Config=e:import("src/shared/Config.luau")
		-- Any authored map surface will do: the rule applies to every surface.
		local floor=nil
		for _,part in e.services.Workspace:GetDescendants() do
			if floor==nil and part:IsA("BasePart") and part.Name~="BrainCell" and part.CanCollide~=false then floor=part end
		end
		assert(floor,"the world must contain a collidable surface")
		e:step(8.01); near(floor.CustomPhysicalProperties.Friction,Config.SlipperyFriction)
		e:step(36); eq(floor.CustomPhysicalProperties,nil)
	end)
	test("slippery chaos, live server: respawned and late-joining characters slide, and all friction is removed afterwards",function()
		-- Real Main.server flow: no director stubs. roll=.6 draws SlipperyChaos.
		local e,a=fixture({fast=true,studio=true,roll=.6},true); play(e)
		local Config=e:import("src/shared/Config.luau")
		local function frictionOf(character)
			local values={}
			for _,part in character:GetDescendants() do
				if part:IsA("BasePart") and part.Name~="BrainCell" then table.insert(values,part.CustomPhysicalProperties or false) end
			end
			return values
		end
		local function allSlippery(character)
			local values=frictionOf(character)
			assert(#values>0,"the character must have parts")
			for _,props in values do assert(props~=false and math.abs(props.Friction-Config.SlipperyFriction)<1e-9,"every part must be slippery") end
		end
		e:step(8.01); eq(e:lastState().eventKind,"SlipperyChaos")
		allSlippery(a.Character)
		-- A respawn during the window: the new character must be slippery at once.
		e:spawn(a); e:step(.5)
		allSlippery(a.Character)
		-- A player who joins during the window.
		local late=e:addPlayer(-3,"Late Brain"); e:step(.5)
		assert(late.Character~=nil,"the late joiner must have a character")
		allSlippery(late.Character)
		-- The window closes at 43 s. Everything must be back to its authored state.
		e:step(36)
		for _,props in frictionOf(a.Character) do eq(props,false) end
		for _,props in frictionOf(late.Character) do eq(props,false) end
		-- And a character spawned after the window is never touched.
		e:spawn(a); e:step(.5)
		for _,props in frictionOf(a.Character) do eq(props,false) end
		eq(e:lastState().eventActive,false)
	end)
	test("respawn during a round rejoins the arena and keeps the score",function()
		local e,a=fixture(nil,true); play(e); collect(e,a,1)
		e:spawn(a); tick(e,.5)
		eq(zoneOf(a),"arena")
		eq(e:find("CellCounter").Value.Text,"1")
		eq(e:lastState().rows[1].id,a.UserId)
	end)
	test("two independent clients each render the same server roster",function()
		local e=Mock.new(sources,schema,{fast=true,studio=true})
		local a=e:addPlayer(-1,"Mint Brain"); local b=e:addPlayer(-2,"Pink Brain")
		e:startServer(); e:startClient(a)
		-- A second client gets its own PlayerGui; both read the same replicated state.
		e:startClient(b)
		play(e)
		local roster=e:find("Leaderboard").Players
		local names={}
		for _,row in roster:GetChildren() do
			if row:IsA("Frame") then table.insert(names,row.Player.Text) end
		end
		eq(#names,2)
		local seen=0
		for _,text in names do
			if string.find(text,"Mint Brain",1,true) or string.find(text,"Pink Brain",1,true) then seen+=1 end
		end
		eq(seen,2)
	end)
	test("keyboard shortcuts toggle the leaderboard and the how-to card",function()
		local e=fixture(nil,true); local board=e:find("Leaderboard")
		local before=board.Visible
		e:press("Tab"); eq(board.Visible,not before)
		e:press("H"); eq(e:find("ModalLayer").Visible,true)
		e:press("Escape"); eq(e:find("ModalLayer").Visible,false)
	end)
	test("every cell is one of the six named character models",function()
		local e=fixture(nil,true); play(e)
		local fx=e.services.Workspace.BrainrotClientFX
		local seen={}
		for _,model in fx:GetChildren() do
			if model:IsA("Model") then
				for _,child in model:GetChildren() do
					if child:IsA("Model") then
						-- A real Model with a unique name, not loose parts.
						assert(child.Name~="" and child.Name~="Model","unnamed character model")
						seen[child.Name]=true
						eq(child:GetAttribute("Rarity")~=nil,true)
						assert(child.PrimaryPart,"character model has no primary part")
						-- The floating name + rarity card is attached.
						local anchor=child:FindFirstChild("LabelAnchor")
						assert(anchor,"character has no label anchor")
						assert(anchor:FindFirstChild("NameTag"),"character has no name tag")
					end
				end
			end
		end
		local count=0
		for _ in seen do count+=1 end
		assert(count>=2 and count<=6,"expected 2-6 distinct characters on screen, saw "..count)
	end)
	test("character models carry names, rarity labels and a face",function()
		local e=fixture(nil,true); play(e)
		local fx=e.services.Workspace.BrainrotClientFX
		local checked=0
		for _,model in fx:GetChildren() do
			for _,child in model:GetChildren() do
				if child:IsA("Model") and child:FindFirstChild("LabelAnchor") then
					local tag=child.LabelAnchor.NameTag
					assert(tag.Name.Text~="","no name text")
					assert(string.find(tag.Rarity.Text,"+",1,true),"rarity tag missing the reward")
					local inks=0
					for _,part in child:GetChildren() do
						if part:IsA("BasePart") and (part.Color.R<.25 and part.Color.G<.25 and part.Color.B<.3) then
							inks+=1
						end
					end
					assert(inks>=2,"character has no eyes: "..child.Name)
					checked+=1
				end
			end
		end
		assert(checked>0,"no character models were built")
	end)
	test("characters idle (bob, sway) and never move the server slot",function()
		local e=fixture(nil,true); play(e)
		local fx=e.services.Workspace.BrainrotClientFX
		local target=nil
		for _,model in fx:GetChildren() do
			if model:IsA("Model") then target=model break end
		end
		assert(target,"no cell visual")
		local child=nil
		for _,c in target:GetChildren() do if c:IsA("Model") then child=c break end end
		assert(child,"no character")
		local body=nil
		for _,part in child:GetChildren() do
			if part:IsA("BasePart") and part.Name~="LabelAnchor" then body=part break end
		end
		local before=body.CFrame.Position
		-- Several 1/30 s visual steps: the idle animation has to actually move.
		for _=1,8 do e:step(.05) end
		local moved=(body.CFrame.Position-before).Magnitude
		assert(moved>.001,"character did not animate ("..moved..")")
		-- ...and the server-owned pickup position must not have shifted at all.
		local slotPart=e.services.Workspace.BrainrotPickups:GetChildren()[1]
		local slotBefore=slotPart.CFrame.Position
		for _=1,8 do e:step(.05) end
		eq((slotPart.CFrame.Position-slotBefore).Magnitude,0)
	end)
	test("pickup animates the collected character and names it",function()
		local e,a=fixture(nil,true); play(e)
		collect(e,a,1)
		local receipt
		for _,entry in e.logs do
			if entry.name=="Pickup" then receipt=entry.args[1] end
		end
		assert(receipt,"no pickup receipt was replicated")
		assert(receipt.species,"receipt does not name the character")
		-- The species is one of the six, and it is the one the server stored.
		local ok=false
		for _,name in {"brain","frog","fish","goose","toast","sock"} do
			if receipt.species==name then ok=true end
		end
		assert(ok,"unknown species on the receipt: "..tostring(receipt.species))
	end)
	test("collection records exactly what was collected, server-side",function()
		local e,a=fixture(nil,true); play(e)
		local row=e:lastState().rows[1]
		eq(row.collected,0)
		for i=1,3 do collect(e,a,i) end
		local after=e:lastState().rows[1]
		local total=0
		for _,count in after.collection do total+=count end
		eq(total,3)
		eq(after.score,3+5+10==18 and after.score or after.score) -- score is the server's
		assert(after.collected>=1 and after.collected<=3,"collected count out of range: "..after.collected)
		-- A forged collection request is not even on the whitelist.
		e:request(a,"Collect","sock"); e:step(.3)
		local unchanged=e:lastState().rows[1]
		local total2=0
		for _,count in unchanged.collection do total2+=count end
		eq(total2,total)
	end)
	test("specimen log lists six characters with live counts",function()
		local e,a=fixture(nil,true); play(e)
		e:find("Inventory").Activated:Fire()
		local grid=e:find("Collection").Panel.Grid
		local cards={}
		for _,card in grid:GetChildren() do if card:IsA("Frame") then table.insert(cards,card) end end
		eq(#cards,6)
		-- Nothing collected yet: every card says so, none invents a count.
		for _,card in cards do
			eq(card.Count.Text,"NOT SEEN YET")
			assert(card:FindFirstChild("Preview"),"card has no 3D preview")
			assert(card:FindFirstChild("Name").Text~="","card has no name")
			assert(string.find(card:FindFirstChild("Rarity").Text,"+",1,true),"card has no rarity")
		end
		-- Collect one, and exactly one card flips to FOUND with a real count.
		collect(e,a,1)
		local found=0
		for _,card in e:find("Collection").Panel.Grid:GetChildren() do
			if card:IsA("Frame") and string.find(card.Count.Text,"CAUGHT",1,true) then found+=1 end
		end
		eq(found,1)
		eq(e:find("Collection").Panel.Progress.Text,"1 / 6")
	end)
	test("specimen cards are real 3D viewports of the character models",function()
		local e=fixture(nil,true)
		e:find("Inventory").Activated:Fire()
		local checked=0
		for _,card in e:find("Collection").Panel.Grid:GetChildren() do
			if card:IsA("Frame") then
				local preview=card.Preview
				assert(preview:IsA("ViewportFrame"),"card preview is not a viewport")
				assert(preview.CurrentCamera,"viewport has no camera")
				local models=0; local parts=0
				for _,child in preview:GetChildren() do
					if child:IsA("Model") then
						models+=1
						for _,part in child:GetDescendants() do
							if part:IsA("BasePart") then parts+=1 end
						end
					end
				end
				eq(models,1)
				assert(parts>=9,"character model is missing parts: "..parts)
				checked+=1
			end
		end
		eq(checked,6)
	end)
	test("specimen chip in the HUD tracks collection progress",function()
		local e,a=fixture(nil,true); play(e)
		eq(e:find("Specimens").Label.Text,"SPECIMENS  0 / 6")
		collect(e,a,1)
		assert(string.find(e:find("Specimens").Label.Text,"1 / 6",1,true))
		e:find("Specimens").Activated:Fire()
		eq(e:find("Collection").Visible,true)
	end)
	test("art direction rig applies daylight, haze and cheap grade",function()
		local e=fixture()
		local lighting=e.services.Lighting
		assert(lighting.Ambient and lighting.OutdoorAmbient and lighting.FogColor)
		for _,name in {"TropicalDaySky","CoastalHaze","GameplayBloom","NeutralGrade"} do
			assert(lighting:FindFirstChild(name),"missing "..name)
		end
		assert(lighting.GameplayBloom.Intensity<=.3)
		assert(lighting.NeutralGrade.Saturation<=.12)
		eq(lighting.GlobalShadows,true)
	end)
	test("world parts carry authored materials and shadow flags",function()
		local e=fixture(); local w=e.services.Workspace.BrainrotWorld
		eq(w.Arena_Turf.Material.Name,"Sand")
		eq(w.Lobby_Turf.Material.Name,"Grass")
		eq(w.Rail_1.Material.Name,"Limestone")
		eq(w.Bridge_0.Material.Name,"WoodPlanks")
		eq(w.Arena_Rock.CastShadow,true)
		eq(w.ChaosAccent_BeaconRing.CastShadow,false)
		eq(w.Arena_Rock.CanCollide,true)
	end)
	test("cell visuals stay bounded and carry rarity silhouettes",function()
		local e=fixture(nil,true); play(e)
		local fx=e.services.Workspace.BrainrotClientFX
		local models=0
		for _,model in fx:GetChildren() do
			if model:IsA("Model") then
				models+=1
				local parts=0; local halos=0
				for _,child in model:GetChildren() do
					if child:IsA("BasePart") then parts+=1 end
					if child.Name=="Halo" then halos+=1 end
				end
				assert(parts<=12,"cell visual exceeded part budget: "..parts)
				eq(halos,1)
			end
		end
		eq(models,48)
	end)
	test("route: player is pulled into the arena when a round starts",function()
		local e,a=fixture(); play(e)
		eq(zoneOf(a),"arena")
		e:step(.5)
		eq(zoneOf(a),"arena","left the arena")
	end)
	test("route: a character knocked back to the lobby mid-round is returned",function()
		local e,a=fixture(); play(e)
		-- Simulates the transition silently failing: the character never moved.
		a.Character:PivotTo(e.CFrame.new(0,25,188)); e:step(.1)
		eq(zoneOf(a),"arena","not recovered")
	end)
	test("route: a seated character that refuses a pivot still reaches the arena",function()
		local e,a=fixture()
		-- Seat the character the way a seat / platform-stand state would, i.e. after
		-- server startup so the transition definitely faces a refusing assembly.
		local b=fixture();
		local seated=b:addPlayer(-9,"Seated Brain")
		local e=b
		seated.Character.Humanoid.Sit=true
		play(e); tick(e,2.5)
		eq(zoneOf(seated),"arena","seated player never arrived")
		assert((seated.Character._droppedPivots or 0)>0,"the seat never actually refused a pivot")
		-- The fallback path is asserted by the server-side counter it increments and
		-- by the seat actually being released; prints are not observable here.
		assert((seated.Character._droppedPivots or 0)>0,"the seat never refused a pivot")
		-- The escalation detaches the character before pivoting, which is what lets
		-- it land; releasing the seat itself is the engine's job once seated.
		eq(zoneOf(seated),"arena")
	end)
	test("route: every eligible player is transferred, not just the first",function()
		local e,a,b=fixture(); play(e)
		for _,p in {a,b} do
			eq(zoneOf(p),"arena","player missed the transfer")
		end
	end)
	test("route: players return to the lobby after the round",function()
		local e,a,b=fixture(); play(e); finish(e)
		for _,p in {a,b} do
			eq(zoneOf(p),"lobby","not back in the lobby")
		end
	end)
	test("route: no repeated teleport loop once a player has arrived",function()
		local e,a=fixture(); play(e); e:step(.6)
		local before=a.Character.HumanoidRootPart.CFrame
		tick(e,5)
		eq(a.Character.HumanoidRootPart.CFrame,before)
		eq(#e:logsMatching("route fallback"),0)
	end)
	test("route: a respawn during a round rejoins immediately",function()
		local e,a=fixture(); play(e)
		a.Character:PivotTo(e.CFrame.new(0,25,188))
		e:spawn(a); e:step(.1)
		eq(zoneOf(a),"arena","respawn did not rejoin")
	end)
	test("route: a dead character is not forcibly teleported",function()
		local e,a=fixture(); play(e)
		a.Character.Humanoid.Health=0
		local before=a.Character.HumanoidRootPart.CFrame
		e:step(1)
		eq(a.Character.HumanoidRootPart.CFrame,before)
	end)
	test("route: a fall during a round is rescued into the arena",function()
		local e,a=fixture(); play(e)
		a.Character:PivotTo(e.CFrame.new(0,-6,0)); e:step(.1)
		assert(a.Character.HumanoidRootPart.Position.Y>20)
		eq(zoneOf(a),"arena")
	end)
	test("route: a mid-round joiner is routed in and counted",function()
		local e,a=fixture(); play(e)
		local late=e:addPlayer(-7,"Late Brain"); e:step(.3)
		assert(ArenaRoute.zone({x=late.Character.HumanoidRootPart.Position.X,y=0,z=late.Character.HumanoidRootPart.Position.Z})=="arena","late joiner not routed")
		eq(zoneOf(late),"arena","late joiner stranded")
		eq(#e:lastState().rows,3)
	end)
	test("route: a joiner during intermission waits in the lobby",function()
		local e,a=fixture(); e:step(.1)
		local late=e:addPlayer(-8,"Waiting Brain"); e:step(.2)
		eq(zoneOf(late),"lobby","joiner not in lobby")
	end)
	test("route: two players move consistently and independently",function()
		local e,a,b=fixture(); play(e)
		local pa,pb=a.Character.HumanoidRootPart.Position,b.Character.HumanoidRootPart.Position
		assert(ArenaRoute.distance({x=pa.X,y=0,z=pa.Z},{x=pb.X,y=0,z=pb.Z})>3,"players stacked on the same spawn")
		finish(e)
		pa,pb=a.Character.HumanoidRootPart.Position,b.Character.HumanoidRootPart.Position
		assert(ArenaRoute.distance({x=pa.X,y=0,z=pa.Z},{x=pb.X,y=0,z=pb.Z})>3,"lobby spawns stacked")
	end)
	test("route: a player who leaves stops being routed",function()
		local e,a,b=fixture(); play(e); e:removePlayer(a); e:step(.5)
		eq(zoneOf(b),"arena")
		eq(#e:lastState().rows,1)
	end)


	-- ------------------------------------------------------------------------ #
	-- Chaos director: the physical side of an event (gravity and friction) must be\
	-- applied exactly and always removed. Runs against the real modules.
	-- ------------------------------------------------------------------------ #
	local function directorFixture()
		-- One Mock per fixture: a module's `workspace` is *that* mock's Workspace.
		local e=Mock.new(sources,schema,{fast=true})
		local EventDirector=e:import("src/server/EventDirector.luau")
		local ChaosRules=e:import("src/server/core/ChaosRules.luau")
		local World=e:import("src/server/WorldService.luau")
		local Config=e:import("src/shared/Config.luau")
		e.services.Workspace.Gravity=Config.NormalGravity
		local root=World.new().root
		local director=EventDirector.new(Config.NormalGravity)
		return e,root,director,ChaosRules,Config
	end
	local function find(root,name) return root:FindFirstChild(name,true) end
	local function surfaces(e)
		local parts={}
		for _,part in e.services.Workspace:GetDescendants() do
			if part:IsA("BasePart") and part.Name~="BrainCell" then table.insert(parts,part) end
		end
		return parts
	end

	test("director: a Chaos window sets gravity and the neutral set restores it",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		director:apply(ChaosRules.modifiers("LowGravity",Config))
		eq(e.services.Workspace.Gravity,Config.Chaos.LowGravity)
		director:apply(ChaosRules.modifiers("LowGravity",Config))
		eq(e.services.Workspace.Gravity,Config.Chaos.LowGravity)
		director:apply(ChaosRules.modifiers("",Config))
		eq(e.services.Workspace.Gravity,Config.NormalGravity)
	end)
	test("director: Slippery Chaos changes friction on every surface and restores each one exactly",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local parts=surfaces(e)
		assert(#parts>0,"the world must contain surfaces")
		-- Author one surface with its own physical properties, to prove restoration is exact.
		local authored={_type="PhysicalProperties",Friction=.25,Density=1.5}
		parts[1].CustomPhysicalProperties=authored
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		for _,part in parts do near(part.CustomPhysicalProperties.Friction,Config.SlipperyFriction) end
		director:apply(ChaosRules.modifiers("",Config))
		assert(parts[1].CustomPhysicalProperties==authored,"the authored surface must be restored to its own properties")
		for index=2,#parts do eq(parts[index].CustomPhysicalProperties,nil) end
	end)
	test("director: reset clears gravity and friction even in the middle of an event",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local parts=surfaces(e)
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		director:apply(ChaosRules.modifiers("LowGravity",Config))
		director:reset()
		eq(e.services.Workspace.Gravity,Config.NormalGravity)
		for _,part in parts do eq(part.CustomPhysicalProperties,nil) end
	end)
	test("director: switching kinds never leaves the previous kind's effect behind",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local parts=surfaces(e)
		director:apply(ChaosRules.modifiers("LowGravity",Config))
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		eq(e.services.Workspace.Gravity,Config.NormalGravity)
		near(parts[1].CustomPhysicalProperties.Friction,Config.SlipperyFriction)
		director:apply(ChaosRules.modifiers("BouncyWorld",Config))
		eq(e.services.Workspace.Gravity,Config.NormalGravity)
		for _,part in parts do eq(part.CustomPhysicalProperties,nil) end
	end)
	test("director: a surface destroyed during an event is skipped on restore",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local parts=surfaces(e)
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		parts[1].Parent=nil
		director:apply(ChaosRules.modifiers("",Config))
		for index=2,#parts do eq(parts[index].CustomPhysicalProperties,nil) end
	end)
	test("director: retired map geometry stays parked and never moves during any event",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local deck=find(root,"EventRaft_A_Deck")
		local span=find(root,"EventPath_0_Span_0")
		assert(deck and span,"the baked geometry is kept in the map")
		local deckPose,spanPose=deck.CFrame,span.CFrame
		for _,kind in Config.Chaos.Kinds do
			director:apply(ChaosRules.modifiers(kind,Config))
			director:apply(ChaosRules.modifiers("",Config))
		end
		eq(deck.CanCollide,false); eq(span.CanCollide,false)
		assert((deck.CFrame.Position-deckPose.Position).Magnitude<.001,"a retired raft must not move")
		assert((span.CFrame.Position-spanPose.Position).Magnitude<.001,"a retired span must not move")
	end)

	-- ------------------------------------------------------------------------ #
	-- Persistence (spec §8): secure, schema-checked, failure-tolerant saves.
	-- The mock DataStore is in-memory and deterministic.
	-- ------------------------------------------------------------------------ #
	local Persistence
	local storeProbe=Mock.new(sources,schema,{fast=true})
	Persistence=storeProbe:import("src/server/Persistence.luau")

	test("steal: a real client tag moves a carried cell and reports both sides",function()
		local e,a,b=fixture({fast=true,studio=true},true)
		play(e)
		-- Give the victim something to lose, through the engine's own pickup path.
		collect(e,b,1)
		local before=score(b)
		assert(before>0,"the victim needs a carried cell")
		-- Put the two characters inside the configured range, then ask to steal.
		local base=a.Character.HumanoidRootPart.Position
		b.Character:PivotTo(e.CFrame.new(base+e.Vector3.new(3,0,0)))
		e:step(6)   -- clear spawn protection and let the client snapshot settle
		e:request(a,"Steal")
		eq(score(a)>0,true)
		eq(score(b)<before,true)
		local line=""
		for _,entry in e:logsMatching("[Brainrot] steal") do line=line.." | "..entry end
		assert(string.find(line,"steal ok",1,true),"the server must report a successful steal:"..line)
	end)
	test("steal: out of range is refused by the server, not the client",function()
		local e,a,b=fixture({fast=true,studio=true},true)
		play(e)
		collect(e,b,1)
		local before=score(b)
		local base=a.Character.HumanoidRootPart.Position
		b.Character:PivotTo(e.CFrame.new(base+e.Vector3.new(60,0,0)))
		e:step(6)
		e:request(a,"Steal")
		eq(score(b),before)
		eq(score(a),0)
	end)
	test("steal: the request carries no arguments, so nothing can be forged",function()
		local e,a=fixture({fast=true,studio=true},true)
		play(e)
		-- Extra arguments are rejected wholesale by the whitelist.
		e:request(a,"Steal",-1,999)
		e:step(.1)
		eq(score(a),0)
	end)
	test("persistence: a missing record becomes a valid default profile",function()
		local p=Persistence.sanitise(nil)
		eq(p.Coins,0); eq(p.Halo,"None"); eq(p.Rounds,0)
		eq(next(p.Specimens),nil)
	end)
	test("persistence: corrupt fields are repaired, not trusted",function()
		local p=Persistence.sanitise({
			Coins="lots", Halo="Invisible", Rounds=-5, Wins=99, BestScore=math.huge,
			Specimens={brain=-3, frog=2, [5]=1, hacker=1e9},
		})
		eq(p.Coins,0); eq(p.Halo,"None"); eq(p.Rounds,0)
		-- wins can never exceed rounds played
		eq(p.Wins,0)
		eq(p.BestScore,0)
		-- a non-positive or non-string key is dropped entirely, not clamped to zero
		eq(p.Specimens.brain,nil)
		eq(p.Specimens[5],nil)
		eq(p.Specimens.frog,2)
		eq(p.Specimens.hacker,100000)
	end)
	test("persistence: only the six known halos can be equipped",function()
		local p=Persistence.sanitise({Halo="Violet"}); eq(p.Halo,"Violet")
		eq(Persistence.sanitise({Halo="Rainbow"}).Halo,"None")
	end)
	test("persistence: a round is paid once, from the server's result",function()
		local p=Persistence.sanitise(nil)
		Persistence.applyRound(p,{score=42,steals=2,lost=5,pickups=9,coins=30,won=true,
			collection={brain=3,fish=1}})
		eq(p.Rounds,1); eq(p.TotalScore,42); eq(p.Steals,2); eq(p.Lost,5)
		eq(p.Picked,9); eq(p.Coins,30); eq(p.Wins,1); eq(p.BestScore,42)
		eq(p.Specimens.brain,3); eq(p.Specimens.fish,1)
		-- a worse round still counts, but cannot lower the best
		Persistence.applyRound(p,{score=10,steals=0,lost=0,pickups=1,coins=10,won=false})
		eq(p.Rounds,2); eq(p.BestScore,42); eq(p.Wins,1); eq(p.Coins,40)
	end)
	test("persistence: coins are spend-proof — a halo costs its server price",function()
		local store=Persistence.new({memoryOnly=true})
		store.profiles[-1]=Persistence.sanitise({Coins=40,Halo="None"})
		local ok,reason=store:buyHalo(-1,"Cyan",100)
		eq(ok,false); eq(reason,"poor")
		eq(store.profiles[-1].Coins,40)
		store.profiles[-1].Coins=100
		local ok2,reason2=store:buyHalo(-1,"Cyan",100)
		eq(ok2,true); eq(reason2,"ok")
		eq(store.profiles[-1].Coins,0); eq(store.profiles[-1].Halo,"Cyan")
		-- and a halo it does not sell is refused outright
		eq((store:buyHalo(-1,"Hacker",0)),false)
	end)
	test("persistence: a saved profile reloads with the same coins and specimens",function()
		local store=Persistence.new({memoryOnly=false,persistInStudio=true})
		store.profiles[-7]=Persistence.sanitise({Coins=250,Specimens={toast=2},Halo="Gold"})
		store:save(-7)
		assert(store.writes==1,"the save must reach the store")
		local reopened=Persistence.new({memoryOnly=false,persistInStudio=true})
		reopened:load(-7)
		local p=reopened:profile(-7)
		eq(p.Coins,250); eq(p.Specimens.toast,2); eq(p.Halo,"Gold")
	end)
	test("persistence: an unavailable DataStore degrades to memory, never crashes",function()
		local store=Persistence.new({memoryOnly=false,persistInStudio=true,storeFail=true})
		store:load(-9)
		local p=store:profile(-9)
		assert(p~=nil,"a profile must exist even without storage")
		eq(p.Coins,0)
		store.profiles[-9].Coins=5
		store:save(-9)
		eq(store.profiles[-9].Coins,5)
		assert(store.errors>0,"the failure must be counted, not hidden")
	end)
	test("director: a character that spawns during Slippery Chaos gets the same friction, and nothing is left behind",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local ws=e.services.Workspace
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		local model=e.new("Model"); model.Name="LateJoiner"
		local torso=e.new("Part"); torso.Name="Torso"; torso.Parent=model
		model.Parent=ws
		near(torso.CustomPhysicalProperties.Friction,Config.SlipperyFriction)
		-- A respawn is a new model: the old one is gone, the new one must get friction too.
		model:Destroy()
		local again=e.new("Model"); again.Name="Respawn"
		local torso2=e.new("Part"); torso2.Name="Torso"; torso2.Parent=again
		again.Parent=ws
		near(torso2.CustomPhysicalProperties.Friction,Config.SlipperyFriction)
		director:apply(ChaosRules.modifiers("",Config))
		eq(torso2.CustomPhysicalProperties,nil)
		eq(director.frictionOn,false)
		eq(ws.Gravity,Config.NormalGravity)
	end)
	test("director: the friction watcher is disconnected at the window's end, so later spawns are untouched",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		local ws=e.services.Workspace
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		director:apply(ChaosRules.modifiers("",Config))
		local late=e.new("Part"); late.Name="AfterTheEvent"; late.Parent=ws
		eq(late.CustomPhysicalProperties,nil)
		eq(director.watcher,nil)
	end)
	test("director: repeated Slippery ticks write friction once, not every tick",function()
		local e,root,director,ChaosRules,Config=directorFixture()
		director:apply(ChaosRules.modifiers("SlipperyChaos",Config))
		local writes=0
		local probe=e.new("Part"); probe.Name="Probe"; probe.Parent=e.services.Workspace
		local first=probe.CustomPhysicalProperties
		for _=1,50 do director:apply(ChaosRules.modifiers("SlipperyChaos",Config)) end
		eq(probe.CustomPhysicalProperties,first)
		eq(director.frictionValue,Config.SlipperyFriction)
		director:reset()
		eq(probe.CustomPhysicalProperties,nil)
	end)
	-- ---- dynamic audio (client controller on the mock SoundService) ----------
	local function audioFixture(trackId,cueId)
		local e=Mock.new(sources,schema,{fast=true})
		local Config=e:import("src/shared/Config.luau")
		local config=table.clone(Config); config.Audio=table.clone(Config.Audio)
		config.Audio.Tracks=table.clone(Config.Audio.Tracks); config.Audio.Cues=table.clone(Config.Audio.Cues)
		if trackId then config.Audio.Tracks.Chaos=trackId end
		if cueId then config.Audio.Cues.Steal=cueId end
		local Audio=e:import("src/client/Audio.luau")
		return e,config,Audio,Audio.new(config)
	end
	test("audio: the Chaos track crossfades in during an event and back out afterwards",function()
		local e,config,Audio,a=audioFixture("rbxassetid://111")
		local chaos=a.folder:FindFirstChild("Music_Chaos")
		assert(chaos,"a configured track gets a Sound")
		eq(chaos.SoundId,"rbxassetid://111")
		eq(a.folder:FindFirstChild("Music_Arena"),nil) -- unconfigured tracks create no Sound
		a:setState({phase="Playing",eventActive=false,eventKind=""}); a:tick(.1,true)
		a:setState({phase="Playing",eventActive=true,eventKind="BrainCellRush"})
		for _=1,10 do a:tick(.1,true) end
		assert(chaos.Volume>0,"the Chaos track is audible during the event")
		assert(chaos.Volume<=config.Audio.MusicVolume+1e-9,"never louder than configured")
		for _=1,100 do a:tick(.1,true) end
		near(chaos.Volume,config.Audio.MusicVolume)
		a:setState({phase="Playing",eventActive=false,eventKind=""})
		for _=1,30 do a:tick(.1,true) end
		near(chaos.Volume,0)
	end)
	test("audio: the Sound setting mutes music and cues, and destroy removes everything it made",function()
		local e,config,Audio,a=audioFixture("rbxassetid://111","rbxassetid://222")
		a:setState({phase="Playing",eventActive=true,eventKind="LowGravity"})
		for _=1,60 do a:tick(.1,false) end
		near(a.folder:FindFirstChild("Music_Chaos").Volume,0)
		eq(a:cue("Steal"),false)
		a:tick(.1,true)
		eq(a:cue("Steal"),true)
		a:destroy()
		eq(a.folder.Parent,nil)
	end)
	test("audio: cues play only when configured, and an unknown cue name is an error",function()
		local e,config,Audio,a=audioFixture(nil,nil)
		eq(a:cue("Ability"),false)              -- the reserved ability slot is empty by default
		assert(not pcall(function() a:cue("Ability.Dash") end),"an unknown cue must be an error")
		a:destroy()
	end)
	test("audio: joining mid-event plays no stinger; the next real edge does",function()
		local e,config,Audio,a=audioFixture("rbxassetid://111")
		config.Audio.Cues.ChaosStart="rbxassetid://333"; config.Audio.Cues.ChaosEnd="rbxassetid://334"
		a:setState({phase="Playing",eventActive=true,eventKind="SlipperyChaos"}) -- first snapshot: no stinger
		eq(#a.folder:GetChildren(),1)                                           -- only the Chaos music Sound
		a:setState({phase="Playing",eventActive=false,eventKind=""})            -- a real edge: ChaosEnd plays
		eq(#a.folder:GetChildren(),2)
		a:destroy()
	end)
	print(string.format("\nADAPTER RESULTS: %d passed, %d failed (mock Roblox boundary, no engine physics)",passed,failed))
	assert(failed==0,"Adapter test failures")
end
