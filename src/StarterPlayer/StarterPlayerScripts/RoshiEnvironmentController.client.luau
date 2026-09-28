-- Clear daytime atmosphere and distance visibility, per player only.
local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local RunService=game:GetService("RunService")
local config=game.ReplicatedStorage:WaitForChild("RoshiEnvironment")
local player=Players.LocalPlayer
local stash=Instance.new("Folder"); stash.Name="SavedRoshiLighting"; stash.Parent=script
local active=false
local saved={}
local sky
local originalVisibility={}
local atmospheres={}
local clouds={}
local lightKeys={"ClockTime","Brightness","Ambient","OutdoorAmbient","FogStart","FogEnd"}
local function enter()
 saved={}
 for _,key in ipairs(lightKeys) do saved[key]=Lighting[key] end
 for _,v in ipairs(Lighting:GetChildren()) do
  if v:IsA("Sky") then v.Parent=stash
  elseif v:IsA("Atmosphere") then
   atmospheres[v]={Density=v.Density,Haze=v.Haze,Glare=v.Glare,Color=v.Color,Decay=v.Decay}
   v.Density=.18;v.Haze=0;v.Glare=0;v.Color=Color3.fromRGB(195,224,255);v.Decay=Color3.fromRGB(220,235,255)
  end
 end
 for _,v in ipairs(workspace.Terrain:GetChildren()) do if v:IsA("Clouds") then clouds[v]=v.Enabled;v.Enabled=false end end
 sky=Instance.new("Sky");sky.Name="RoshiClearBlueSky";sky.StarCount=0;sky.CelestialBodiesShown=true
 sky.Parent=Lighting
 Lighting.ClockTime=13;Lighting.Brightness=2.5;Lighting.Ambient=Color3.fromRGB(145,165,185);Lighting.OutdoorAmbient=Color3.fromRGB(175,195,215);Lighting.FogStart=1500;Lighting.FogEnd=10000
end
local function leave()
 if sky then sky:Destroy();sky=nil end
 for _,v in ipairs(stash:GetChildren()) do v.Parent=Lighting end
 for key,value in pairs(saved) do Lighting[key]=value end
 for v,props in pairs(atmospheres) do if v.Parent then for k,value in pairs(props) do v[k]=value end end end
 for v,enabled in pairs(clouds) do if v.Parent then v.Enabled=enabled end end
 atmospheres={};clouds={}
end
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<.2 then return end;elapsed=0
 local character=player.Character
 local root=character and character:FindFirstChild("HumanoidRootPart")
 local center=config:GetAttribute("Center")
 local radius=config:GetAttribute("Radius")
 local inside=false
 if root and center and radius then
  local p=root.Position;inside=Vector2.new(p.X-center.X,p.Z-center.Z).Magnitude<radius and math.abs(p.Y-center.Y)<600
 end
 if inside~=active then active=inside;if active then enter() else leave() end end
 local island=workspace:FindFirstChild("RoshiHouse")
 if island then
  for _,v in ipairs(island:GetDescendants()) do
   if v:IsA("BasePart") then
    if originalVisibility[v]==nil then originalVisibility[v]=v.LocalTransparencyModifier end
    v.LocalTransparencyModifier=inside and 0 or 1
   elseif v:IsA("BillboardGui") or v:IsA("SurfaceGui") then
    if originalVisibility[v]==nil then originalVisibility[v]=v.Enabled end
    v.Enabled=inside and originalVisibility[v] or false
   end
  end
 end
end)
