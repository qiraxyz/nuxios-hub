--!strict
-- SmoothHub.lua
-- A tiny, smooth, and modern script-hub UI library (Tabs, Sections, Toggles, Sliders, Dropdowns, Buttons, Keybinds, TextInput)
-- No external dependencies. Works in Studio & live games.
-- Parent resolves to CoreGui if possible, else PlayerGui.

--///////////////////////////////
-- Utilities
--///////////////////////////////
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local function lerp(a:number, b:number, t:number) return a + (b-a)*t end

local function tween(o:Instance, t:number, props:any, es:Enum.EasingStyle?, ed:Enum.EasingDirection?)
	local info = TweenInfo.new(t, es or Enum.EasingStyle.Quad, ed or Enum.EasingDirection.Out)
	return TweenService:Create(o, info, props)
end

local function safeParent()
	local s = (gethui and gethui()) or (syn and syn.protect_gui and Instance.new("ScreenGui")) or nil
	if s then
		if not s.Parent then s.Parent = game:GetService("CoreGui") end
		return s
	end
	local cg = game:GetService("CoreGui")
	local ok = pcall(function() local _ = cg.Name end)
	if ok then
		local g = Instance.new("ScreenGui")
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		g.Parent = cg
		return g
	end
	local plr = game.Players.LocalPlayer
	local pg = plr:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = pg
	return g
end

local function make(className:string, props:any?, children:{Instance}?)
	local o = Instance.new(className)
	if props then
		for k,v in pairs(props) do
			(o :: any)[k] = v
		end
	end
	if children then
		for _,c in ipairs(children) do c.Parent = o end
	end
	return o
end

local function ripple(button:Instance)
	if not (button:IsA("TextButton") or button:IsA("ImageButton")) then return end
	local absSize = button.AbsoluteSize
	local circle = make("Frame", {
		BackgroundColor3 = Color3.fromRGB(255,255,255),
		BackgroundTransparency = 0.85,
		Size = UDim2.fromOffset(0,0),
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		ClipsDescendants = true,
		ZIndex = (button.ZIndex or 1) + 1
	},{
		make("UICorner", {CornerRadius = UDim.new(1,0)})
	})
	circle.Parent = button
	local radius = math.max(absSize.X, absSize.Y) * 1.25
	tween(circle, 0.35, {Size = UDim2.fromOffset(radius, radius), BackgroundTransparency = 1}):Play()
	task.delay(0.38, function() circle:Destroy() end)
end

local function applyStroke(inst:Instance, c3:Color3, thickness:number, transparency:number)
	local s = make("UIStroke", {Color = c3, Thickness = thickness, Transparency = transparency})
	s.Parent = inst
	return s
end

local function dragify(frame:Frame, handle:Instance?)
	local dragging = false
	local dragStart = Vector2.zero
	local startPos = Vector2.zero
	local dragInput : InputObject? = nil
	local h = handle or frame

	local function update(input:InputObject)
		local delta = input.Position - dragStart
		frame.Position = UDim2.fromOffset(startPos.X + delta.X, startPos.Y + delta.Y)
	end

	h.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or
		input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
			dragInput = input
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	h.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or
		input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			update(input)
		end
	end)
end

--///////////////////////////////
-- Library
--///////////////////////////////
export type ToggleOpts = {default:boolean?, callback:(boolean)->()?, key?:string?}
export type SliderOpts = {min:number, max:number, default:number?, step:number?, callback:(number)->()?, key?:string?}
export type DropdownOpts = {options:{string}, default:string?, callback:(string)->()?, key?:string?}
export type KeybindOpts = {default:Enum.KeyCode?, callback:(Enum.KeyCode)->()?, key?:string?}
export type TextOpts = {placeholder:string?, default:string?, callback:(string)->()?, key?:string?}
export type ButtonOpts = {callback:(()->())?}

export type Section = {
	Toggle:(self:any, label:string, opts:ToggleOpts?)->(),
	Slider:(self:any, label:string, opts:SliderOpts)->(),
	Dropdown:(self:any, label:string, opts:DropdownOpts)->(),
	Keybind:(self:any, label:string, opts:KeybindOpts)->(),
	TextInput:(self:any, label:string, opts:TextOpts)->(),
	Button:(self:any, label:string, opts:ButtonOpts?)->(),
	Label:(self:any, text:string)->(),
	Separator:(self:any)->(),
}

export type Tab = {
	Section:(self:any, name:string)->Section
}

export type Window = {
	Tab:(self:any, name:string, iconId:string?)->Tab,
	Notify:(self:any, title:string, message:string, duration:number?)->(),
	Minimize:(self:any)->(),
	Destroy:(self:any)->(),
	SaveState:(self:any)->(),
	LoadState:(self:any)->(),
}

local SmoothHub = {}

-- Theme
local THEME = {
	bg = Color3.fromRGB(20,20,25),
	panel = Color3.fromRGB(27,27,34),
	accent = Color3.fromRGB(115, 105, 255),
	soft = Color3.fromRGB(180,180,200),
	text = Color3.fromRGB(235,235,245),
	muted = Color3.fromRGB(150,150,170)
}

local DEFAULTS = {
	title = "SmoothHub",
	key = "smoothhub_state.json",
	drag_padding = 12,
}

-- State store (simple JSON via HttpService + writefile if available)
local function canWrite() return (writefile and isfile and readfile) ~= nil end
local function saveJSON(name:string, tbl:any)
	if not canWrite() then return end
	local ok, data = pcall(function() return HttpService:JSONEncode(tbl) end)
	if ok then
		pcall(writefile, name, data)
	end
end
local function loadJSON(name:string)
	if not (canWrite() and isfile and readfile and isfile(name)) then return nil end
	local ok, str = pcall(readfile, name)
	if not ok then return nil end
	local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, str)
	return ok2 and decoded or nil
end

--///////////////////////////////
-- Window creation
--///////////////////////////////
function SmoothHub:Window(opts:{title:string?, key:string?}?): Window
	opts = opts or {}
	local title = opts.title or DEFAULTS.title
	local stateKey = opts.key or DEFAULTS.key

	local root = safeParent()

	local screen = (function()
		if root:IsA("ScreenGui") then return root end
		local g = Instance.new("ScreenGui")
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		g.Parent = root
		return g
	end)()

	local main = make("Frame", {
		Size = UDim2.fromOffset(620, 420),
		Position = UDim2.fromOffset(100, 100),
		BackgroundColor3 = THEME.bg,
		BorderSizePixel = 0
	},{
		make("UICorner", {CornerRadius = UDim.new(0,16)}),
		make("UIPadding", {PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12), PaddingTop = UDim.new(0,12), PaddingBottom = UDim.new(0,12)}),
	})
	main.Parent = screen
	applyStroke(main, THEME.accent, 1.5, 0.5)

	local header = make("Frame", {
		Size = UDim2.new(1, -24, 0, 42),
		Position = UDim2.fromOffset(12,12),
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true
	},{
		make("UICorner", {CornerRadius = UDim.new(0,12)}),
		make("UIPadding", {PaddingLeft = UDim.new(0,14), PaddingRight = UDim.new(0,8)})
	})
	header.Parent = main
	applyStroke(header, Color3.fromRGB(255,255,255), 1, 0.9)

	local titleLbl = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1,1),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamBold,
		TextSize = 18
	})
	titleLbl.Parent = header

	local topBtns = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1,0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(120, 28)
	},{
		make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,8), HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center})
	})
	topBtns.Parent = header

	local minimize = make("TextButton", {
		Text = "—",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.bg,
		Size = UDim2.fromOffset(34, 26),
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamBold,
		TextSize = 14
	},{
		make("UICorner", {CornerRadius = UDim.new(0,8)})
	})
	minimize.Parent = topBtns
	applyStroke(minimize, THEME.soft, 1, 0.35)

	local close = make("TextButton", {
		Text = "✕",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.bg,
		Size = UDim2.fromOffset(34, 26),
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamBold,
		TextSize = 14
	},{
		make("UICorner", {CornerRadius = UDim.new(0,8)})
	})
	close.Parent = topBtns
	applyStroke(close, Color3.fromRGB(255,90,90), 1, 0.35)

	local leftTabs = make("Frame", {
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 66),
		Size = UDim2.fromOffset(160, main.AbsoluteSize.Y - 78),
	})
	leftTabs.Parent = main
	applyStroke(leftTabs, Color3.fromRGB(255,255,255), 1, 0.94)
	make("UICorner", {CornerRadius = UDim.new(0,12)}).Parent = leftTabs

	local tabsList = make("ScrollingFrame", {
		Active = true, CanvasSize = UDim2.new(0,0,0,0), ScrollBarThickness = 3,
		BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4,4),
	})
	tabsList.Parent = leftTabs
	make("UIListLayout", {Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder}).Parent = tabsList

	local content = make("Frame", {
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(184, 66),
		Size = UDim2.new(1, -196, 1, -78),
		ClipsDescendants = true
	},{
		make("UICorner", {CornerRadius = UDim.new(0,12)}),
		make("UIPadding", {PaddingTop = UDim.new(0,10), PaddingBottom = UDim.new(0,10), PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12)})
	})
	content.Parent = main
	applyStroke(content, Color3.fromRGB(255,255,255), 1, 0.9)

	local pages = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1,1)
	},{
		make("UIPageLayout", {
			Circular = false,
			Padding = UDim.new(0,10),
			EasingStyle = Enum.EasingStyle.Quad,
			EasingDirection = Enum.EasingDirection.Out,
			Animated = true
		})
	})
	pages.Parent = content
	local pageLayout: UIPageLayout = pages:FindFirstChildOfClass("UIPageLayout") :: UIPageLayout

	-- Dragging & window animations
	dragify(main, header)
	main.BackgroundTransparency = 1
	header.BackgroundTransparency = 1
	leftTabs.BackgroundTransparency = 1
	content.BackgroundTransparency = 1
	task.delay(0.03, function()
		tween(main, 0.18, {BackgroundTransparency = 0}):Play()
		tween(header, 0.18, {BackgroundTransparency = 0}):Play()
		tween(leftTabs, 0.18, {BackgroundTransparency = 0}):Play()
		tween(content, 0.18, {BackgroundTransparency = 0}):Play()
	end)

	-- Tab creation
	local currentTabBtn:TextButton? = nil
	local tabs = {}

	local function selectTab(btn:TextButton, page:Frame)
		if currentTabBtn == btn then return end
		if currentTabBtn then
			tween(currentTabBtn, 0.12, {BackgroundColor3 = THEME.bg}):Play()
		end
		currentTabBtn = btn
		tween(btn, 0.12, {BackgroundColor3 = THEME.accent}):Play()
		pageLayout:JumpTo(page)
	end

	local function makeControlRow(parent:Instance, labelText:string)
		local row = make("Frame", {
			BackgroundColor3 = THEME.bg,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 38)
		},{
			make("UICorner", {CornerRadius = UDim.new(0,8)}),
			make("UIPadding", {PaddingLeft = UDim.new(0,10), PaddingRight = UDim.new(0,10)}),
		})
		row.Parent = parent
		applyStroke(row, THEME.soft, 1, 0.9)

		local lbl = make("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 1, 0),
			Text = labelText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = THEME.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 14
		})
		lbl.Parent = row

		return row, lbl
	end

	local state = loadJSON(stateKey) or {}

	-- Section factory
	local function createSection(container:ScrollingFrame, name:string): Section
		local headerS = make("TextLabel", {
			BackgroundTransparency = 1, Text = name,
			Font = Enum.Font.GothamBold, TextColor3 = THEME.soft, TextSize = 15,
			Size = UDim2.new(1,0,0,22), TextXAlignment = Enum.TextXAlignment.Left
		})
		headerS.Parent = container

		local function addToggle(label:string, opts:ToggleOpts?)
			opts = opts or {}
			local default = if opts.default ~= nil then opts.default else false
			local key = opts.key or ("toggle_"..label)
			local on = (state[key] ~= nil) and state[key] or default

			local row, _ = makeControlRow(container, label)
			local sw = make("TextButton", {
				AutoButtonColor = false, Text = "",
				BackgroundColor3 = on and THEME.accent or THEME.bg,
				Size = UDim2.fromOffset(46, 22),
				AnchorPoint = Vector2.new(1,0.5),
				Position = UDim2.new(1, -8, 0.5, 0)
			},{
				make("UICorner", {CornerRadius = UDim.new(1,0)})
			})
			sw.Parent = row
			applyStroke(sw, THEME.soft, 1, 0.2)

			local knob = make("Frame", {
				BackgroundColor3 = Color3.fromRGB(255,255,255),
				Size = UDim2.fromOffset(18,18),
				Position = on and UDim2.fromOffset(26,2) or UDim2.fromOffset(2,2)
			},{
				make("UICorner", {CornerRadius = UDim.new(1,0)})
			})
			knob.Parent = sw

			local function set(v:boolean, animate:boolean?)
				on = v
				state[key] = on
				if animate then tween(sw, 0.12, {BackgroundColor3 = on and THEME.accent or THEME.bg}):Play() else sw.BackgroundColor3 = on and THEME.accent or THEME.bg end
				tween(knob, 0.12, {Position = on and UDim2.fromOffset(26,2) or UDim2.fromOffset(2,2)}):Play()
				if opts.callback then task.spawn(opts.callback, on) end
			end

			sw.MouseButton1Click:Connect(function()
				ripple(sw)
				set(not on, true)
			end)

			-- initial
			set(on, false)
		end

		local function addSlider(label:string, opts:SliderOpts)
			local min,max = opts.min, opts.max
			local step = opts.step or 1
			local key = opts.key or ("slider_"..label)
			local val = (state[key] ~= nil) and state[key] or (opts.default or min)

			local row, _ = makeControlRow(container, label)
			row.Size = UDim2.new(1, -8, 0, 44)

			local valueTxt = make("TextLabel", {
				BackgroundTransparency = 1, Text = tostring(val),
				Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = THEME.muted,
				AnchorPoint = Vector2.new(1,0.5), Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(60, 20), TextXAlignment = Enum.TextXAlignment.Right
			})
			valueTxt.Parent = row

			local bar = make("Frame", {
				BackgroundColor3 = THEME.bg,
				BorderSizePixel = 0, Size = UDim2.new(1, -80, 0, 6),
				Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0,0.5)
			},{
				make("UICorner", {CornerRadius = UDim.new(1,0)})
			})
			bar.Parent = row
			applyStroke(bar, THEME.soft, 1, 0.85)

			local fill = make("Frame", {
				BackgroundColor3 = THEME.accent,
				BorderSizePixel = 0, Size = UDim2.fromScale((val-min)/(max-min), 1)
			},{
				make("UICorner", {CornerRadius = UDim.new(1,0)})
			})
			fill.Parent = bar

			local dragging = false
			local function setFromX(x:number)
				local rel = math.clamp((x - bar.AbsolutePosition.X) / (bar.AbsoluteSize.X), 0, 1)
				local raw = min + (max-min) * rel
				local stepped = math.floor((raw/step)+0.5) * step
				stepped = math.clamp(stepped, min, max)
				val = stepped
				state[key] = val
				fill.Size = UDim2.fromScale((val-min)/(max-min), 1)
				valueTxt.Text = tostring(val)
				if opts.callback then task.spawn(opts.callback, val) end
			end

			bar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragging = true
					setFromX(input.Position.X)
				end
			end)
			bar.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
					setFromX(input.Position.X)
				end
			end)
		end

		local function addDropdown(label:string, opts:DropdownOpts)
			local key = opts.key or ("dropdown_"..label)
			local value = (state[key] ~= nil) and state[key] or (opts.default or (opts.options[1] or ""))

			local row, _ = makeControlRow(container, label)
			row.Size = UDim2.new(1, -8, 0, 76)

			local current = make("TextButton", {
				AutoButtonColor = false, Text = value,
				BackgroundColor3 = THEME.bg, TextColor3 = THEME.text,
				Font = Enum.Font.Gotham, TextSize = 14,
				AnchorPoint = Vector2.new(1,0), Position = UDim2.new(1, -10, 0, 8),
				Size = UDim2.fromOffset(180, 26)
			},{
				make("UICorner", {CornerRadius = UDim.new(0,8)})
			})
			current.Parent = row
			applyStroke(current, THEME.soft, 1, 0.85)

			local list = make("ScrollingFrame", {
				Active = true, BackgroundColor3 = THEME.bg, BorderSizePixel = 0,
				Size = UDim2.fromOffset(180, 34), Position = UDim2.new(1, -10, 0, 40),
				AnchorPoint = Vector2.new(1,0), Visible = false, ScrollBarThickness = 3, ClipsDescendants = true
			},{
				make("UICorner", {CornerRadius = UDim.new(0,8)}),
				make("UIListLayout", {Padding = UDim.new(0,6)}),
				make("UIPadding", {PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,6), PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6)})
			})
			list.Parent = row
			applyStroke(list, THEME.soft, 1, 0.85)

			local function populate()
				for _,c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
				for _,opt in ipairs(opts.options) do
					local b = make("TextButton", {
						AutoButtonColor = false,
						BackgroundColor3 = THEME.panel,
						TextColor3 = THEME.text,
						Font = Enum.Font.Gotham, TextSize = 14,
						Text = opt,
						Size = UDim2.new(1, -0, 0, 26)
					},{
						make("UICorner", {CornerRadius = UDim.new(0,6)})
					})
					b.Parent = list
					b.MouseButton1Click:Connect(function()
						ripple(b)
						value = opt
						state[key] = value
						current.Text = value
						tween(list, 0.12, {Size = UDim2.fromOffset(180, 34)}):Play()
						task.delay(0.12, function() list.Visible = false end)
						if opts.callback then task.spawn(opts.callback, value) end
					end)
				end
				list.CanvasSize = UDim2.new(0,0,0, (#opts.options * 32))
			end
			populate()

			current.MouseButton1Click:Connect(function()
				ripple(current)
				if not list.Visible then
					list.Visible = true
					tween(list, 0.12, {Size = UDim2.fromOffset(180, math.min(150, 34 + (#opts.options * 32)))}):Play()
				else
					tween(list, 0.12, {Size = UDim2.fromOffset(180, 34)}):Play()
					task.delay(0.12, function() list.Visible = false end)
				end
			end)
		end

		local function addKeybind(label:string, opts:KeybindOpts)
			local key = opts.key or ("key_"..label)
			local current:Enum.KeyCode = (state[key] ~= nil) and Enum.KeyCode[state[key]] or (opts.default or Enum.KeyCode.RightShift)

			local row, _ = makeControlRow(container, label)
			local btn = make("TextButton", {
				AutoButtonColor = false, Text = current.Name,
				TextColor3 = THEME.text, BackgroundColor3 = THEME.bg,
				Font = Enum.Font.Gotham, TextSize = 13,
				Size = UDim2.fromOffset(120, 24),
				AnchorPoint = Vector2.new(1,0.5), Position = UDim2.new(1, -8, 0.5, 0)
			},{
				make("UICorner", {CornerRadius = UDim.new(0,8)})
			})
			btn.Parent = row
			applyStroke(btn, THEME.soft, 1, 0.8)

			local capturing = false

			local function setKey(kc:Enum.KeyCode)
				current = kc
				state[key] = kc.Name
				btn.Text = kc.Name
				if opts.callback then task.spawn(opts.callback, kc) end
			end

			btn.MouseButton1Click:Connect(function()
				ripple(btn)
				btn.Text = "Press a key..."
				capturing = true
			end)

			UserInputService.InputBegan:Connect(function(input, gpe)
				if gpe then return end
				if capturing and input.UserInputType == Enum.UserInputType.Keyboard then
					capturing = false
					setKey(input.KeyCode)
				end
			end)
		end

		local function addTextInput(label:string, opts:TextOpts)
			local key = opts.key or ("text_"..label)
			local textVal = (state[key] ~= nil) and state[key] or (opts.default or "")

			local row, _ = makeControlRow(container, label)
			local box = make("TextBox", {
				Text = textVal,
				PlaceholderText = opts.placeholder or "",
				TextColor3 = THEME.text, BackgroundColor3 = THEME.bg,
				Font = Enum.Font.Gotham, TextSize = 14, ClearTextOnFocus = false,
				Size = UDim2.fromOffset(220, 26),
				AnchorPoint = Vector2.new(1,0.5), Position = UDim2.new(1, -8, 0.5, 0)
			},{
				make("UICorner", {CornerRadius = UDim.new(0,8)})
			})
			box.Parent = row
			applyStroke(box, THEME.soft, 1, 0.8)

			box.FocusLost:Connect(function(enter)
				state[key] = box.Text
				if opts.callback then task.spawn(opts.callback, box.Text) end
			end)
		end

		local function addButton(label:string, opts:ButtonOpts?)
			local row, _ = makeControlRow(container, label)
			local btn = make("TextButton", {
				Text = "Run",
				TextColor3 = THEME.text, BackgroundColor3 = THEME.accent,
				Font = Enum.Font.GothamBold, TextSize = 14,
				Size = UDim2.fromOffset(80, 26),
				AnchorPoint = Vector2.new(1,0.5), Position = UDim2.new(1, -8, 0.5, 0),
				AutoButtonColor = false
			},{
				make("UICorner", {CornerRadius = UDim.new(0,8)})
			})
			btn.Parent = row
			applyStroke(btn, THEME.soft, 1, 0.1)

			btn.MouseButton1Click:Connect(function()
				ripple(btn)
				if opts and opts.callback then task.spawn(opts.callback) end
			end)
		end

		local function addLabel(text:string)
			local r = make("TextLabel", {
				BackgroundTransparency = 1, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = THEME.muted, Font = Enum.Font.Gotham,
				Text = text, TextSize = 14, Size = UDim2.new(1, -8, 0, 40)
			})
			r.Parent = container
		end

		local function addSeparator()
			local sep = make("Frame", {BackgroundColor3 = THEME.soft, Size = UDim2.new(1, -8, 0, 1), BorderSizePixel = 0})
			sep.Parent = container
			sep.BackgroundTransparency = 1
			tween(sep, 0.25, {BackgroundTransparency = 0.6}):Play()
		end

		return {
			Toggle = addToggle,
			Slider = addSlider,
			Dropdown = addDropdown,
			Keybind = addKeybind,
			TextInput = addTextInput,
			Button = addButton,
			Label = addLabel,
			Separator = addSeparator,
		}
	end

	local function createTab(name:string, iconId:string?): Tab
		local btn = make("TextButton", {
			Text = name, AutoButtonColor = false,
			BackgroundColor3 = THEME.bg, TextColor3 = THEME.text,
			Font = Enum.Font.GothamBold, TextSize = 14,
			Size = UDim2.new(1, -8, 0, 34)
		},{
			make("UICorner", {CornerRadius = UDim.new(0,8)})
		})
		btn.Parent = tabsList
		applyStroke(btn, THEME.soft, 1, 0.85)

		local pg = make("ScrollingFrame", {
			Active = true, ScrollBarThickness = 4,
			BackgroundTransparency = 1, Size = UDim2.fromScale(1,1), CanvasSize = UDim2.new(0,0,0,0)
		},{
			make("UIListLayout", {Padding = UDim.new(0,8)}),
			make("UIPadding", {PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6), PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,10)})
		})
		pg.Parent = pages

		btn.MouseButton1Click:Connect(function()
			ripple(btn)
			selectTab(btn, pg)
		end)

		-- default select if first
		if #tabs == 0 then
			selectTab(btn, pg)
		end
		table.insert(tabs, {btn=btn, page=pg})

		return {
			Section = function(_, sectionName:string)
				return createSection(pg, sectionName)
			end
		}
	end

	-- Notifications
	local notifyRoot = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1,1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(340, 400)
	},{
		make("UIListLayout", {Padding = UDim.new(0,8), HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom})
	})
	notifyRoot.Parent = screen

	local function notify(titleN:string, msg:string, duration:number?)
		duration = duration or 3
		local card = make("Frame", {
			BackgroundColor3 = THEME.panel, Size = UDim2.new(1, 0, 0, 0),
			BorderSizePixel = 0, ClipsDescendants = true
		},{
			make("UICorner", {CornerRadius = UDim.new(0,12)}),
			make("UIPadding", {PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,12), PaddingTop = UDim.new(0,10), PaddingBottom = UDim.new(0,10)})
		})
		card.Parent = notifyRoot
		applyStroke(card, THEME.soft, 1, 0.8)

		local t = make("TextLabel", {
			BackgroundTransparency = 1, Text = titleN, Font = Enum.Font.GothamBold, TextSize = 15,
			TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1,0,0,20)
		})
		t.Parent = card

		local b = make("TextLabel", {
			BackgroundTransparency = 1, TextWrapped = true, Text = msg, Font = Enum.Font.Gotham, TextSize = 13,
			TextColor3 = THEME.muted, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1,0,0,34)
		})
		b.Parent = card

		card.Size = UDim2.new(1,0,0,0)
		tween(card, 0.16, {Size = UDim2.new(1,0,0,64)}):Play()
		task.delay(duration, function()
			tween(card, 0.16, {Size = UDim2.new(1,0,0,0)}):Play()
			task.delay(0.18, function() card:Destroy() end)
		end)
	end

	-- Minimize & close
	local minimized = false
	local savedSize:UDim2 = main.Size
	minimize.MouseButton1Click:Connect(function()
		ripple(minimize)
		minimized = not minimized
		if minimized then
			savedSize = main.Size
			tween(main, 0.15, {Size = UDim2.fromOffset(savedSize.X.Offset, 66)}):Play()
			tween(content, 0.12, {BackgroundTransparency = 1}):Play()
			content.Visible = false
		else
			content.Visible = true
			tween(main, 0.15, {Size = savedSize}):Play()
			tween(content, 0.12, {BackgroundTransparency = 0}):Play()
		end
	end)

	close.MouseButton1Click:Connect(function()
		ripple(close)
		tween(main, 0.12, {BackgroundTransparency = 1}):Play()
		task.delay(0.13, function() screen:Destroy() end)
	end)

	-- Public API
	local api:Window = {
		Tab = function(_, name:string, iconId:string?)
			return createTab(name, iconId)
		end,
		Notify = function(_, t:string, m:string, d:number?)
			notify(t, m, d)
		end,
		Minimize = function(_)
			minimize:Activate()
		end,
		Destroy = function(_)
			close:Activate()
		end,
		SaveState = function(_)
			saveJSON(stateKey, state)
			notify("Saved", "UI state saved.", 2)
		end,
		LoadState = function(_)
			local loaded = loadJSON(stateKey)
			if loaded then
				for k,v in pairs(loaded) do state[k] = v end
				notify("Loaded", "State loaded. (Re-open to see some controls reflect)", 3)
			else
				notify("No Save", "No saved state found.", 2.5)
			end
		end
	}

	return api
end

return SmoothHub
