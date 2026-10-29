--!nonstrict
-- Runs the actual Main.server, WorldService, Main.client, Hud and Effects sources.
-- Mocks only the Roblox boundary; see TESTING.md for the mandatory Studio acceptance pass.
return function(Mock, sources, schema)
	local passed,failed=0,0
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
		eq(#w:GetChildren(),358)
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
		eq(#initial:GetChildren(),358)
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
	test("low gravity activates and restores actual Workspace property",function()
		local e=fixture(); play(e); e:step(8.01)
		eq(e:lastState().eventActive,true); near(e.services.Workspace.Gravity,62)
		e:step(10.01); eq(e:lastState().eventActive,false); near(e.services.Workspace.Gravity,196.2)
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
		local e,a=fixture({fast=true,studio=true,roll=.97}); play(e)
		for i=1,3 do collect(e,a,i) end
		eq(score(a),30); finish(e); eq(a.leaderstats.Coins.Value,100)
		e:request(a,"Halo"); eq(a.leaderstats.Coins.Value,0); eq(#a.Character.PulseHalo:GetChildren(),8)
		e:spawn(a); eq(#a.Character.PulseHalo:GetChildren(),8)
		e:step(1); e:request(a,"Halo"); eq(a.Character:FindFirstChild("PulseHalo"),nil); eq(a.leaderstats.Coins.Value,0)
	end)
	test("actual client constructs HUD and syncs server snapshot",function()
		local e=fixture(nil,true); e:step(.1)
		assert(e:find("BrainrotHUD")); eq(e:find("YourCells").Score.Text,"0")
		eq(e:find("RoundClock").Phase.Text,"GET READY • AUTO JOIN • TEST")
	end)
	test("actual client updates score only after server pickup",function()
		local e,a=fixture(nil,true); play(e); collect(e,a,1)
		eq(e:find("YourCells").Score.Text,"1")
		e:request(a,"Score",999); e:step(.3); eq(e:find("YourCells").Score.Text,"1")
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
		assert(string.find(card.Winner.Text,"Mint Brain",1,true)); eq(card.Reward.Text,"+42 SESSION COINS")
	end)
	test("help, sound preference and motion controls are functional",function()
		local e=fixture(nil,true)
		e:find("Help").Activated:Fire(); eq(e:find("ModalLayer").Visible,true)
		e:find("Motion").Activated:Fire(); eq(e:find("Motion").Text,"REDUCED MOTION: ON")
		e:find("ModalSound").Activated:Fire(); eq(e:find("ModalSound").Text,"SFX OFF")
		e:find("Close").Activated:Fire(); eq(e:find("ModalLayer").Visible,false)
	end)
	test("ranks toggle hides and shows custom leaderboard",function()
		local e=fixture(nil,true); local board=e:find("Leaderboard"); local previous=board.Visible
		e:find("Ranks").Activated:Fire(); eq(board.Visible,not previous); e:find("Ranks").Activated:Fire(); eq(board.Visible,previous)
	end)
	test("mobile HUD stays inside safe bounds without overlapping top controls",function()
		for _,size in {{320,568},{360,740},{390,800},{430,900},{844,354},{1280,720}} do
			local e=fixture(nil,true); e:setViewport(size[1],size[2])
			local names={"RoundClock","Ranks","Help","Rewards"}
			if size[1]<760 and size[2]>=500 then
				local scoreRect=rect(e:find("YourCells"))
				assert(not overlaps(scoreRect,{x=0,y=size[2]-105,w=110,h=105}),"Score blocks joystick")
				assert(not overlaps(scoreRect,{x=size[1]-110,y=size[2]-105,w=110,h=105}),"Score blocks jump")
			end
			for i,name in names do
				local a=rect(e:find(name)); assert(a.x>=0 and a.y>=0 and a.x+a.w<=size[1]+1 and a.y+a.h<=size[2]+1,"Out of bounds: "..name)
				for j=i+1,#names do assert(not overlaps(a,rect(e:find(names[j]))),"Overlap at "..size[1]..": "..name.." / "..names[j]) end
			end
		end
	end)
	test("mobile cosmetic modal sends only the validated halo verb",function()
		local e,a=fixture(nil,true); e:setViewport(390,800)
		e:find("Rewards").Activated:Fire(); e:find("Action").Activated:Fire()
		eq(a.leaderstats.Coins.Value,0); eq(a.Character:FindFirstChild("PulseHalo"),nil)
		eq(e:find("Message").Text,"Not enough session coins")
	end)
	print(string.format("\nADAPTER RESULTS: %d passed, %d failed (mock Roblox boundary, no engine physics)",passed,failed))
	assert(failed==0,"Adapter test failures")
end
