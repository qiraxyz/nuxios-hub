---
--- Created by Kerlolio.
--- DateTime: 11/11/2025 19:00
---

local Nxs = loadstring(game:HttpGet(
'https://raw.githubusercontent.com/qiraxyz/nuxios-hub/refs/heads/main/packages/mainGui.lua'))()

local win = Nxs:Window({ title = "My Script Hub", key = "myhub_state.json" })

local mainTab = win:Tab("Main")
local cfgTab  = win:Tab("Config")
local about   = win:Tab("About")

-- Main
local s1 = mainTab:Section("Core Controls")
s1:Toggle("Auto Farm", { default = true, key = "autofarm", callback = function(on)
    print("[Auto Farm]", on)
end})

s1:Slider("Speed", { min=1, max=50, default=20, step=1, key="speed", callback=function(v)
    print("Speed:", v)
end})

s1:Dropdown("Mode", { options={"Legit","Semi","Rage"}, default="Semi", key="mode", callback=function(opt)
    print("Mode:", opt)
end})

s1:Keybind("Show/Hide UI", { default = Enum.KeyCode.RightShift, key="toggle_key", callback=function(kc)
    print("Keybind set to", kc)
end})

s1:Button("Notify", { callback=function()
    win:Notify("Hello!", "This is a smooth notification.", 2.5)
end})

-- Config
local s2 = cfgTab:Section("State")
s2:TextInput("Profile Name", { placeholder="default", key="profile", callback=function(txt)
    print("Profile:", txt)
end})
s2:Button("Save State", { callback = function() win:SaveState() end })
s2:Button("Load State", { callback = function() win:LoadState() end })
s2:Separator()
s2:Label("Tip: State uses writefile/readfile if available; falls back to memory if not.")

-- About
local s3 = about:Section("Info")
s3:Label("SmoothHub — minimal, animated, and easy to extend.\nTabs > Sections > Controls.\nDrag window, minimize, notifications included.")