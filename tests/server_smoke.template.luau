-- Server gameplay tests. Sources are injected by tools/check.py at execution time.
local now = 10
local delayed = {}
local task = {delay = function(seconds, fn) table.insert(delayed, {at = now + seconds, fn = fn}) end}
local os = {clock = function() return now end}
local function advance(seconds)
 local target = now + seconds
 while true do
  local chosen = nil
  for i, job in ipairs(delayed) do
   if job.at <= target and (not chosen or job.at < delayed[chosen].at) then chosen = i end
  end
  if not chosen then break end
  local job = table.remove(delayed, chosen)
  now = job.at
  job.fn()
 end
 now = target
end
local function event()
 local self = {callbacks = {}}
 function self:Connect(fn) table.insert(self.callbacks, fn) end
 function self:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
 return self
end
local vectorMeta = {__sub = function(a,b) return {Magnitude=math.abs(a.x-b.x)} end}
local function vector(x) return setmetatable({x=x or 0}, vectorMeta) end
local function node(className, name)
 local self = {ClassName=className,Name=name or className,children={},Position=vector(0)}
 function self:IsA(c) return self.ClassName == c or (c == 'BasePart' and self.ClassName == 'Part') end
 function self:FindFirstChild(n) return self.children[n] end
 function self:WaitForChild(n) assert(self.children[n], 'Missing fake child '..n); return self.children[n] end
 function self:FindFirstChildOfClass(c) for _,child in pairs(self.children) do if child.ClassName==c then return child end end end
 function self:FireAllClients(payload) self.last=payload end
 function self:FireClient(_,payload) self.last=payload end
 if className=='RemoteEvent' then self.OnServerEvent=event() end
 if className=='ProximityPrompt' then self.PromptButtonHoldBegan=event(); self.Triggered=event() end
 return setmetatable(self,{__newindex=function(t,k,v) rawset(t,k,v); if k=='Parent' and v then v.children[t.Name]=t end end})
end
local Instance = {new=function(c) return node(c) end}
local Color3 = {fromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
local Random = {new=function() return {NextInteger=function(_,a,_) return a end} end}
local Enum = {KeyCode={E='E',ButtonX='X'},ProximityPromptExclusivity={OnePerButton='One'}}
local workspace = node('Workspace','Workspace')
local map = node('Model','MidnightGarage'); map.Parent=workspace
for _,n in ipairs({'InspectionPoint','RepairWheel','RepairOil','RepairLights','RejectPoint','UpgradePoint','DispatchPoint'}) do local a=node('Part',n); a.Parent=map end
local replicated = node('ReplicatedStorage','ReplicatedStorage')
local shared = node('Folder','MidnightGarage'); shared.Parent=replicated
local configModule=node('ModuleScript','Config'); configModule.Parent=shared
local server=node('Folder','MidnightGarage')
local worldModule=node('ModuleScript','World'); worldModule.Parent=server
local script={Parent=server}
local players = node('Players','Players'); players.PlayerAdded=event(); players.PlayerRemoving=event()
function players:GetPlayers() return {} end
local game={GetService=function(_,n) return n=='Players' and players or replicated end}
local fakeWorld={}
function fakeWorld:SpawnCar(c) self.current=c end
function fakeWorld:SetCarState(a) self.anomaly=a end
function fakeWorld:RemoveCar() self.current=nil end
function fakeWorld:SetDoor(v) self.closed=v end
function fakeWorld:Repair(k) self.repaired=k end
function fakeWorld:Flash(c) self.flash=c end
local CONFIG = (function()
__CONFIG_SOURCE__
end)()

local require = function(module) return module==configModule and CONFIG or {new=function() return fakeWorld end} end
local function runMain()
__SERVER_SOURCE__
end
runMain()

local remotes=shared.children.Remotes
local stateRemote=remotes.children.State
local action=remotes.children.Action
local notice=remotes.children.Notify
local player=node('Player','Tester'); player.Parent=players
player.Character=node('Model','Character')
local root=node('Part','HumanoidRootPart'); root.Parent=player.Character
local humanoid=node('Humanoid','Humanoid'); humanoid.Health=100; humanoid.Parent=player.Character
local function state() return stateRemote.last end
local ids={inspect='InspectionPoint',wheel='RepairWheel',oil='RepairOil',lights='RepairLights',reject='RejectPoint',upgrade='UpgradePoint',next='DispatchPoint'}
local function prompt(id) return map.children[ids[id]].children.Interact end
local function hold(id)
 local p=prompt(id); assert(p.Enabled,'Prompt disabled: '..id)
 p.PromptButtonHoldBegan:Fire(player)
 advance(p.HoldDuration + .02)
 p.Triggered:Fire(player)
end
local function send(kind) action.OnServerEvent:Fire(player,{type=kind}) end
local function check(ok,label) assert(ok,label); print('PASS '..label) end
local function finishCurrentCorrectly()
 hold('inspect')
 if fakeWorld.current.anomaly then
  hold('reject')
 else
  local t=state().tasks
  hold(t[1].id)
  hold(t[2].id)
 end
 advance(2)
end
advance(1)
check(state().phase=='serving' and state().customerIndex==1,'automatic safe first customer')
check(fakeWorld.current.anomaly==nil,'first customer has no anomaly')
prompt('inspect').Triggered:Fire(player)
check(not state().inspected,'forged prompt without holding rejected')
hold('wheel')
check(not state().tasks[1].done and state().cash==0,'repair before inspection does not progress')
root.Position=vector(100)
prompt('inspect').PromptButtonHoldBegan:Fire(player); advance(1); prompt('inspect').Triggered:Fire(player)
check(not state().inspected,'far prompt rejected')
send('inspect'); check(not state().inspected,'far inspection remote rejected')
root.Position=vector(0)
finishCurrentCorrectly()
check(state().phase=='between' and state().cash==60,'normal repairs pay exactly once')
send('next'); advance(1)
check(state().customerIndex==2 and state().phase=='serving','next GUI advances valid transition')
send('next'); check(state().customerIndex==2,'cannot skip active customer')
finishCurrentCorrectly()
check(state().cash==120,'second normal reward')
root.Position=vector(100); send('upgrade'); check(state().upgradeLevel==0,'far upgrade remote rejected')
root.Position=vector(0)
hold('upgrade')
check(state().cash==20 and state().upgradeLevel==1,'upgrade charges server price')
check(prompt('wheel').HoldDuration<CONFIG.RepairDuration,'upgrade reduces repair duration')
hold('next'); advance(1)
check(fakeWorld.current.anomaly~=nil,'scheduled anomaly appears')
hold('inspect'); check(state().inspected and string.find(state().hint,'Cierra')~=nil,'inspection exposes usable anomaly clue')
hold(state().tasks[1].id)
check(state().errors==1 and state().cash==0,'repairing anomaly causes one error and bounded penalty')
prompt('reject').Triggered:Fire(player)
check(state().errors==1,'resolved customer cannot be paid or penalized twice')
advance(2)
hold('next'); advance(1)
check(fakeWorld.current.anomaly~=nil,'second anomaly exists')
hold('reject'); advance(2)
check(state().cash==45,'correct anomaly rejection pays reward')
hold('next'); advance(1); finishCurrentCorrectly()
check(state().phase=='ended' and state().shiftComplete,'fifth customer ends completed shift')
check(state().cash==205 and state().summary.earned==305 and state().summary.correct==4,'shift reward, penalties and upgrade accounting')
local priorCash=state().cash
send('restart'); advance(1)
check(state().shift==2 and state().cash==priorCash and state().upgradeLevel==1,'restart resets shift and preserves session progress')
hold('reject'); advance(2)
for i=1,4 do
 if state().phase=='ended' then break end
 hold('next'); advance(1)
 if fakeWorld.current.anomaly then hold('inspect'); hold(state().tasks[1].id) else hold('reject') end
 advance(2)
end
check(state().phase=='ended' and state().errors==3 and not state().shiftComplete,'third error ends shift without completion bonus')
advance(1); send('sync')
local rev=state().revision
send('sync'); check(state().revision==rev,'sync requests rate limited')
action.OnServerEvent:Fire(player,{type=string.rep('x',1000)})
action.OnServerEvent:Fire(player,'malformed')
check(state().revision==rev,'malformed remote payloads ignored')
print('SERVER SMOKE TESTS PASSED')
