--!nonstrict
-- Contract-test doubles, NOT the Roblox engine. No physics, renderer, networking, or audio.
-- The real server and client scripts execute against these services in adapter tests.
local Mock = {}

local function signal()
	local listeners = {}
	local s = {}
	function s:Connect(fn)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, { connection = connection, fn = fn })
		return connection
	end
	function s:Fire(...)
		for _, listener in table.clone(listeners) do
			if listener.connection.Connected then listener.fn(...) end
		end
	end
	return s
end

local V = {}
local vmt = {}
vmt.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X*self.X+self.Y*self.Y+self.Z*self.Z) end
	if key == "Unit" then return self / self.Magnitude end
	return V[key]
end
vmt.__add = function(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vmt.__sub = function(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vmt.__mul = function(a,b) if type(a)=="number" then a,b=b,a end; return V.new(a.X*b,a.Y*b,a.Z*b) end
vmt.__div = function(a,b) return V.new(a.X/b,a.Y/b,a.Z/b) end
function V.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0,_type="Vector3"},vmt) end
function V:Cross(b) return V.new(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
V.zero = V.new()

local CF = {}
local cfmt
cfmt = { __index = function(self,key)
	if key=="Position" then return self.p end
	if key=="Rotation" then return setmetatable({p=V.zero,r=self.r,_type="CFrame"},cfmt) end
	return CF[key]
end }
local function rotate(r,v)
	return V.new(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z)
end
cfmt.__mul = function(a,b)
	if b._type=="Vector3" then return a.p+rotate(a.r,b) end
	local r={}
	for row=0,2 do for col=0,2 do
		r[row*3+col+1]=a.r[row*3+1]*b.r[col+1]+a.r[row*3+2]*b.r[col+4]+a.r[row*3+3]*b.r[col+7]
	end end
	return setmetatable({p=a.p+rotate(a.r,b.p),r=r,_type="CFrame"},cfmt)
end
function CF.new(x,y,z)
	local p=if type(x)=="table" then x else V.new(x,y,z)
	return setmetatable({p=p,r={1,0,0,0,1,0,0,0,1},_type="CFrame"},cfmt)
end
function CF.Angles(x,y,z)
	local cx,cy,cz,sx,sy,sz=math.cos(x),math.cos(y),math.cos(z),math.sin(x),math.sin(y),math.sin(z)
	return setmetatable({p=V.zero,r={cy*cz,-cy*sz,sy,cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy,sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy},_type="CFrame"},cfmt)
end
function CF.lookAt(eye,target)
	local back=(eye-target).Unit
	local right=V.new(0,1,0):Cross(back).Unit
	local up=back:Cross(right)
	return setmetatable({p=eye,r={right.X,up.X,back.X,right.Y,up.Y,back.Y,right.Z,up.Z,back.Z},_type="CFrame"},cfmt)
end
function CF:Inverse()
	local r=self.r
	local inverse={r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]}
	return setmetatable({p=rotate(inverse,self.p)*-1,r=inverse,_type="CFrame"},cfmt)
end

local Color = {}
local colormt = {__index=Color}
function Color.new(r,g,b) return setmetatable({R=r or 0,G=g or 0,B=b or 0,_type="Color3"},colormt) end
function Color.fromRGB(r,g,b) return Color.new(r/255,g/255,b/255) end
function Color:Lerp(other,t) return Color.new(self.R+(other.R-self.R)*t,self.G+(other.G-self.G)*t,self.B+(other.B-self.B)*t) end
local UDim = {new=function(s,o) return {Scale=s,Offset=o} end}
local UDim2 = {
	new=function(xs,xo,ys,yo) return {X=UDim.new(xs,xo),Y=UDim.new(ys,yo),_type="UDim2"} end,
}
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local Vector2 = {new=function(x,y) return {X=x,Y=y,_type="Vector2"} end,zero={X=0,Y=0}}

function Mock.new(sources, schema, options)
	options = options or {}
	local env = { now=100, viewport={X=1280,Y=720}, logs={}, delayed={}, modules={}, sources=sources, options=options }
	local enum={}
	for enumName,items in schema.Enums do
		local values={}
		for name,value in items do values[name]={Name=name,Value=value,_type="EnumItem"} end
		enum[enumName]=setmetatable(values,{__index=function(_,key) error("Invalid enum: "..enumName.."."..key) end})
	end
	local function classIs(class,base)
		if class==base then return true end
		local definition=schema.Classes[class]
		return definition~=nil and definition.Superclass~=nil and classIs(definition.Superclass,base)
	end
	local function propertyExists(class,key)
		local definition=schema.Classes[class]
		if not definition then return false end
		return definition.Properties[key]~=nil or (definition.Superclass~=nil and propertyExists(definition.Superclass,key))
	end
	local methods={}
	local function children(obj) return table.clone(obj._children) end
	local instanceMt={}
	local function absoluteSize(obj)
		if obj:IsA("ScreenGui") then return env.viewport end
		local size=obj._props.Size or UDim2.fromScale(0,0)
		local ps=if obj._props.Parent then absoluteSize(obj._props.Parent) else env.viewport
		return {X=ps.X*size.X.Scale+size.X.Offset,Y=ps.Y*size.Y.Scale+size.Y.Offset}
	end
	local function absolutePosition(obj)
		local parent=obj._props.Parent
		if not parent or obj:IsA("ScreenGui") then return {X=0,Y=0} end
		local pp=absolutePosition(parent)
		local ps=absoluteSize(parent)
		local size=absoluteSize(obj)
		local pos=obj._props.Position or UDim2.fromOffset(0,0)
		local anchor=obj._props.AnchorPoint or Vector2.zero
		return {X=pp.X+ps.X*pos.X.Scale+pos.X.Offset-size.X*anchor.X,Y=pp.Y+ps.Y*pos.Y.Scale+pos.Y.Offset-size.Y*anchor.Y}
	end
	instanceMt.__index=function(obj,key)
		if key=="ClassName" then return obj._class end
		if methods[key] then return methods[key] end
		if key=="Position" and obj:IsA("BasePart") then return (obj._props.CFrame or CF.new()).Position end
		if key=="AbsoluteSize" then return absoluteSize(obj) end
		if key=="AbsolutePosition" then return absolutePosition(obj) end
		if obj._props[key]~=nil then return obj._props[key] end
		if obj._signals[key] then return obj._signals[key] end
		for _,child in obj._children do if child.Name==key then return child end end
		return nil
	end
	instanceMt.__newindex=function(obj,key,value)
		if string.sub(key,1,1)=="_" then rawset(obj,key,value); return end
		assert(propertyExists(obj._class,key),"Unknown property "..obj._class.."."..key)
		if key=="Parent" then
			local old=obj._props.Parent
			if old==value then return end
			if old then
				local index=table.find(old._children,obj)
				if index then table.remove(old._children,index) end
			end
			obj._props.Parent=value
			if old then old.ChildRemoved:Fire(obj) end
			if value then table.insert(value._children,obj); value.ChildAdded:Fire(obj) end
			obj.AncestryChanged:Fire(obj,value)
		elseif key=="Position" and obj:IsA("BasePart") then
			obj._props.CFrame=CF.new(value)*(obj._props.CFrame or CF.new()).Rotation
		else obj._props[key]=value end
		if obj._propertySignals[key] then obj._propertySignals[key]:Fire() end
	end
	local function new(class)
		assert(schema.Classes[class],"Unknown Roblox class: "..class)
		local obj=setmetatable({_class=class,_props={Name=class},_children={},_signals={},_attributes={},_propertySignals={}},instanceMt)
		for _,key in {"ChildAdded","ChildRemoved","AncestryChanged","Destroying","AttributeChanged","Activated","OnServerEvent","OnClientEvent","CharacterAdded","PlayerAdded","PlayerRemoving","Heartbeat","RenderStepped","InputBegan"} do obj._signals[key]=signal() end
		if obj:IsA("BasePart") then obj._props.CFrame=CF.new(); obj._props.Color=Color.new(1,1,1) end
		if obj:IsA("GuiObject") then obj._props.Visible=true; obj._props.Size=UDim2.fromOffset(0,0); obj._props.Position=UDim2.fromOffset(0,0) end
		if class=="Humanoid" then obj._props.Health=100 end
		if class=="IntValue" then obj._props.Value=0 end
		return obj
	end
	function methods:IsA(class) return classIs(self._class,class) end
	function methods:GetChildren() return children(self) end
	function methods:GetDescendants()
		local result={}
		for _,child in self._children do
			table.insert(result,child)
			for _,desc in child:GetDescendants() do table.insert(result,desc) end
		end
		return result
	end
	function methods:FindFirstChild(name,recursive)
		for _,child in self._children do if child.Name==name then return child end end
		if recursive then for _,child in self._children do local found=child:FindFirstChild(name,true); if found then return found end end end
		return nil
	end
	function methods:WaitForChild(name) local child=self:FindFirstChild(name); assert(child,"Mock missing child "..self.Name.."/"..name); return child end
	function methods:FindFirstChildOfClass(class) for _,child in self._children do if child:IsA(class) then return child end end; return nil end
	function methods:SetAttribute(key,value) self._attributes[key]=value; self.AttributeChanged:Fire(key) end
	function methods:GetAttribute(key) return self._attributes[key] end
	function methods:GetPropertyChangedSignal(key) if not self._propertySignals[key] then self._propertySignals[key]=signal() end; return self._propertySignals[key] end
	function methods:Destroy()
		if self._destroyed then return end
		self._destroyed=true
		self.Destroying:Fire()
		for _,child in children(self) do child:Destroy() end
		self.Parent=nil
	end
	function methods:ClearAllChildren() for _,child in children(self) do child:Destroy() end end
	function methods:GetPivot()
		if self.PrimaryPart then return self.PrimaryPart.CFrame end
		if self._pivot then return self._pivot end
		for _,part in self:GetDescendants() do if part:IsA("BasePart") then return part.CFrame end end
		return CF.new()
	end
	function methods:PivotTo(cf)
		local delta=cf*self:GetPivot():Inverse()
		for _,part in self:GetDescendants() do if part:IsA("BasePart") then part.CFrame=delta*part.CFrame end end
		self._pivot=cf
	end
	function methods:GetServerTimeNow() return env.now end
	function methods:GetPlayers() local result={}; for _,child in self._children do if child:IsA("Player") then table.insert(result,child) end end; return result end
	function methods:IsStudio() return options.studio~=false end
	function methods:GetFocusedTextBox() return nil end
	function methods:SetCoreGuiEnabled() end
	function methods:Play() self._played=true end
	function methods:FireAllClients(...)
		table.insert(env.logs,{name=self.Name,args={...},player=nil})
		self.OnClientEvent:Fire(...)
	end
	function methods:FireClient(player,...)
		table.insert(env.logs,{name=self.Name,args={...},player=player.UserId})
		if player==env.services.Players.LocalPlayer then self.OnClientEvent:Fire(...) end
	end
	function methods:FireServer(...) self.OnServerEvent:Fire(env.services.Players.LocalPlayer,...) end
	function methods:Create(target,_,properties)
		return {Play=function() for key,value in properties do target[key]=value end end}
	end
	function methods:AddItem(object,delay) table.insert(env.delayed,{at=env.now+delay,fn=function() object:Destroy() end}) end
	env.new=new
	env.Vector3,env.CFrame=V,CF
	env.services={}
	env.game=new("DataModel")
	for _,name in {"Workspace","Players","ReplicatedStorage","ServerScriptService","StarterPlayer","Lighting","SoundService","RunService","TweenService","UserInputService","Debris","StarterGui"} do
		local service=new(name); service.Name=name; service.Parent=env.game; env.services[name]=service
	end
	function methods:GetService(name) assert(env.services[name],"Unknown service "..name); return env.services[name] end
	local camera=new("Camera"); camera.CFrame=CF.new(0,45,70); camera.Parent=env.services.Workspace
	env.services.Workspace.CurrentCamera=camera
	local starterScripts=new("StarterPlayerScripts"); starterScripts.Parent=env.services.StarterPlayer
	local function folder(parent,name) local f=new("Folder"); f.Name=name; f.Parent=parent; return f end
	local shared=folder(env.services.ReplicatedStorage,"BrainrotShared")
	local server=folder(env.services.ServerScriptService,"BrainrotServer")
	local core=folder(server,"core")
	local client=folder(starterScripts,"BrainrotClient")
	local nodes={}
	for path in sources do
		local name=string.match(path,"([^/]+)%.luau$")
		local class="ModuleScript"
		if string.find(name,".server",1,true) then name=string.gsub(name,"%.server$",""); class="Script" end
		if string.find(name,".client",1,true) then name=string.gsub(name,"%.client$",""); class="LocalScript" end
		local parent=if string.find(path,"src/shared/",1,true) then shared elseif string.find(path,"src/server/core/",1,true) then core elseif string.find(path,"src/server/",1,true) then server else client
		local node=new(class); node.Name=name; node.Parent=parent; node._sourcePath=path; nodes[path]=node
	end
	env.nodes=nodes
	local globals={
		print=function(...) end, warn=function(...) end,
		game=env.game,workspace=env.services.Workspace,Instance={new=new},Enum=enum,
		Vector3=V,Vector2=Vector2,CFrame=CF,Color3=Color,UDim=UDim,UDim2=UDim2,
		TweenInfo={new=function(...) return {...} end},
		Random={new=function() return {NextNumber=function() return options.roll or .1 end} end},
		task={spawn=function(fn,...) fn(...) end,wait=function() return 0 end,delay=function(delay,fn) table.insert(env.delayed,{at=env.now+delay,fn=fn}) end},
		typeof=function(value) return if type(value)=="table" then (value._type or (if value._class then "Instance" else "table")) else type(value) end,
	}
	local loading={}
	local function import(node)
		assert(type(node)=="table" and node._sourcePath,"Mock require expects a ModuleScript")
		if env.modules[node]~=nil then return env.modules[node] end
		assert(not loading[node],"Circular module import")
		loading[node]=true
		local source=sources[node._sourcePath]
		if options.fast and node.Name=="Config" then source=string.gsub(source,"StudioFastMode = false,","StudioFastMode = true,") end
		local fn,err=loadstring(source,"@"..node._sourcePath)
		assert(fn,err)
		local scope=setmetatable({script=node,require=import},{__index=function(_,key) return globals[key] or getfenv()[key] end})
		setfenv(fn,scope)
		local result=fn()
		env.modules[node]=if result==nil then true else result
		loading[node]=nil
		return result
	end
	function env:import(path) return import(nodes[path]) end
	function env:startServer() self:import("src/server/Main.server.luau") end
	function env:startClient(player)
		self.services.Players.LocalPlayer=player
		self:import("src/client/Main.client.luau")
	end
	function env:spawn(player)
		local old=player.Character
		if old then old:Destroy() end
		local character=new("Model"); character.Name=player.Name
		local root=new("Part"); root.Name="HumanoidRootPart"; root.CFrame=CF.new(0,25,188); root.Parent=character
		local head=new("Part"); head.Name="Head"; head.CFrame=CF.new(0,28,188); head.Parent=character
		local humanoid=new("Humanoid"); humanoid.Parent=character
		character.PrimaryPart=root; character.Parent=self.services.Workspace
		player.Character=character
		player.CharacterAdded:Fire(character)
		return character
	end
	function env:addPlayer(id,name)
		local player=new("Player"); player.Name=name; player.DisplayName=name; player.UserId=id; player.Parent=self.services.Players
		local gui=new("PlayerGui"); gui.Parent=player
		self:spawn(player)
		self.services.Players.PlayerAdded:Fire(player)
		return player
	end
	function env:removePlayer(player)
		self.services.Players.PlayerRemoving:Fire(player)
		if player.Character then player.Character:Destroy() end
		player:Destroy()
	end
	function env:step(dt)
		self.now+=dt
		self.services.RunService.Heartbeat:Fire(dt)
		self.services.RunService.RenderStepped:Fire(dt)
		local scheduled=self.delayed; self.delayed={}
		for _,item in scheduled do if item.at<=self.now then item.fn() else table.insert(self.delayed,item) end end
	end
	function env:request(player,...)
		self.services.ReplicatedStorage.BrainrotRemotes.Request.OnServerEvent:Fire(player,...)
	end
	function env:lastState()
		for i=#self.logs,1,-1 do if self.logs[i].name=="State" then return self.logs[i].args[1] end end
		return nil
	end
	function env:find(name)
		return self.game:FindFirstChild(name,true)
	end
	function env:setViewport(width,height)
		self.viewport={X=width,Y=height}
		for _,object in self.game:GetDescendants() do
			if object._propertySignals.AbsoluteSize then object._propertySignals.AbsoluteSize:Fire() end
		end
	end
	return env
end
return Mock
