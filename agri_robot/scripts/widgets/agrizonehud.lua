-- Floating zone badges and the chest-like zone plan editor.
-- Lives in widgets/controls (see modmain). Badges follow the world position
-- of their zone's upper centre on screen; one editor at a time opens next to
-- its badge. The slots are PLAN selectors only: they hold no items, real
-- seeds still come from the robots and the warehouse.
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local ImageButton=require("widgets/imagebutton")
local Text=require("widgets/text")
local TextButton=require("widgets/textbutton")
local C=require("agri/constants")
local Fields=require("agri/field_zones")

local ROBOT_RANGE=64        -- poll only with a robot this close
local HIDE_DISTANCE=48      -- badges of zones farther away hide
local BADGE_W,BADGE_H=176,64
local PANEL_W,PANEL_H=500,460
local SLOT_COLUMNS,SLOT_ROWS=4,2
local STATE_TEXT={ok="",editing="编辑中",paused="已暂停",review="待确认方案",unsafe="密度无法排布",empty="未设置方案"}
local MODE_TEXT={ratio="比例填满",exact="精确数量"}
local REASON_TEXT={OFFGRID_PLANT="旁边有不在网格上的作物",LAYOUT_OBSTRUCTED="地面不可耕作",NEIGHBOR_NATURAL_HOLE="相邻自然坑待清理",
    ADJACENT_ZONE_SPACING="与相邻田块孔距不足",PLOW_IN_PROGRESS="耕地机工作中",NEED_HOE="缺少园艺锄"}

local function send(request)
    local network=require("agri/network")
    if network.SendZone then network.SendZone(request) end
end
local plant_defs
local function defs()
    if plant_defs==nil then
        local ok,data=pcall(require,"prefabs/farm_plant_defs")
        plant_defs=ok and type(data)=="table" and data.PLANT_DEFS or {}
    end
    return plant_defs
end
-- Crop id -> inventory icon prefab, seed prefab and display name.
local function cropinfo(id)
    if id=="randomseed" then return {icon="seeds",seed="seeds",name="通用种子"} end
    local def=defs()[id] or {}
    local product=def.product or id
    local name=STRINGS.NAMES and STRINGS.NAMES[string.upper(tostring(product))] or tostring(id)
    return {icon=product,seed=def.seed or (tostring(id).."_seeds"),name=name}
end
local function icon(parent,prefab,size)
    local tex=tostring(prefab)..".tex"
    local ok,atlas=pcall(GetInventoryItemAtlas,tex,true)
    if ok and type(atlas)=="string" then
        local image=parent:AddChild(Image(atlas,tex))
        image:SetSize(size,size);image:SetClickable(false)
        return image
    end
    -- Text fallback when the native atlas has no such icon.
    local label=parent:AddChild(Text(BODYTEXTFONT,math.floor(size*.45),cropinfo(prefab).name))
    label:SetClickable(false)
    return label
end
local function label(parent,text,x,y,size,colour)
    local t=parent:AddChild(Text(BODYTEXTFONT,size or 18,tostring(text or "")))
    t:SetPosition(x,y);t:SetClickable(false)
    if colour then t:SetColour(colour[1],colour[2],colour[3],colour[4] or 1) end
    return t
end
local function textbutton(parent,text,x,y,fn,size)
    local b=parent:AddChild(TextButton())
    b:SetText(text);b:SetTextSize(size or 18);b:SetPosition(x,y);b:SetOnClick(fn)
    b:SetTextColour(.92,.86,.68,1);b:SetTextFocusColour(1,1,1,1)
    return b
end
local function panelbg(parent,w,h,tint)
    local bg=parent:AddChild(Image("images/global.xml","square.tex"))
    bg:SetSize(w,h);bg:SetTint(tint[1],tint[2],tint[3],tint[4])
    return bg
end
local function scales()
    local w,h=TheSim:GetScreenSize()
    local prop=math.min(w/RESOLUTION_X,h/RESOLUTION_Y,MAX_HUD_SCALE or 1.25)
    local hud=TheFrontEnd and TheFrontEnd.GetHUDScale and TheFrontEnd:GetHUDScale() or 1
    return w,h,prop,hud
end
local function validentry(e)
    if type(e)~="table" or type(e.id)~="string" or not e.id:match("^z%d+$") or type(e.pts)~="table" then return false end
    if #e.pts<2 or #e.pts%2~=0 or #e.pts>C.ZONE_POINTS_MAX*2 then return false end
    for _,v in ipairs(e.pts) do if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return false end end
    return true
end
local function describe(settings)
    if type(settings)~="table" then return "—" end
    local field=settings.mode=="exact" and "counts" or "weights"
    local parts={}
    local keys={};for k in pairs(settings[field] or {}) do keys[#keys+1]=k end;table.sort(keys)
    for _,k in ipairs(keys) do parts[#parts+1]=cropinfo(k).name..tostring(settings[field][k]) end
    return (MODE_TEXT[settings.mode] or "").." "..tostring(settings.density).."孔 "..(#parts>0 and table.concat(parts," ") or "空")
end

-- Badge -------------------------------------------------------------------------
local Badge=Class(Widget,function(self,hud,id)
    Widget._ctor(self,"AgriZoneBadge")
    self.hud,self.id=hud,id
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(MAX_HUD_SCALE)
    self.content=self:AddChild(Widget("content"))
    self.button=self.content:AddChild(ImageButton("images/global.xml","square.tex"))
    self.button:ForceImageSize(BADGE_W,BADGE_H)
    self.button.scale_on_focus=false;self.button.move_on_click=false
    self.button:SetImageNormalColour(.09,.11,.07,.82);self.button:SetImageFocusColour(.18,.23,.13,.94)
    self.button:SetOnClick(function() hud:Toggle(id) end)
    self.title=label(self.content,"",0,19,17,{.95,.9,.72,1})
    self.icons=self.content:AddChild(Widget("icons"));self.icons:SetPosition(0,-1)
    self.status=label(self.content,"",0,-21,15,{.85,.85,.8,1})
end)
function Badge:SetData(entry)
    self.entry=entry
    local tiles,density=tonumber(entry.n) or 0,tonumber(entry.d) or 0
    self.title:SetString("田块 #"..entry.id:sub(2).." · "..tiles.."格×"..density.."孔")
    self.icons:KillAllChildren()
    local crops=type(entry.tg)=="table" and entry.tg or {}
    local shown=math.min(3,#crops)
    for i=1,shown do
        local crop=crops[i]
        if type(crop)=="table" and type(crop.c)=="string" then
            local x=(i-(shown+1)/2)*54
            local image=icon(self.icons,cropinfo(crop.c).icon,24);image:SetPosition(x-12,0)
            label(self.icons,tostring(crop.h or 0).."/"..tostring(crop.n or 0),x+14,0,14)
        end
    end
    if shown==0 then label(self.icons,"点击设置种植方案",0,0,15,{.8,.8,.7,1}) end
    local state=STATE_TEXT[entry.st] or ""
    local miss=tonumber(entry.miss) or 0
    -- Plan progress (planted planned crops / planned total). Payloads
    -- without tt/td fall back to the summed listed crops, then plants on
    -- slots / usable capacity.
    local done,total=tonumber(entry.td),tonumber(entry.tt)
    if not (done and total) then
        local sd,st=0,0
        for _,crop in ipairs(crops) do
            if type(crop)=="table" then
                local n=tonumber(crop.n) or 0
                st=st+n;sd=sd+math.max(0,math.min(tonumber(crop.h) or 0,n))
            end
        end
        if st>0 then done,total=sd,st else done,total=tonumber(entry.pl) or 0,tonumber(entry.use) or 0 end
    end
    local text="方案 "..tostring(done).."/"..tostring(total)
    if miss>0 then text=text.." · 缺种 "..miss end
    if state~="" then text=state.." · "..text end
    self.status:SetString(text)
    if entry.st=="review" or entry.st=="unsafe" or miss>0 then self.status:SetColour(1,.62,.45,1) else self.status:SetColour(.85,.85,.8,1) end
end

-- Editor ------------------------------------------------------------------------
local Editor=Class(Widget,function(self,hud,detail)
    Widget._ctor(self,"AgriZoneEditor")
    self.hud=hud
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(MAX_HUD_SCALE)
    self.content=self:AddChild(Widget("content"))
    panelbg(self.content,PANEL_W+8,PANEL_H+8,{.42,.34,.22,.96})
    panelbg(self.content,PANEL_W,PANEL_H,{.13,.11,.08,.96})
    self.body=self.content:AddChild(Widget("body"))
    self.notice=""
    self.slot_page,self.pick_page=1,1
    self:Load(detail,true)
end)
-- reset=true (open, saved, stale) replaces the draft and closes the picker.
-- A heartbeat (reset=false) never touches unsaved edits; with nothing
-- unsaved it refreshes the draft but keeps slot order, pages and picker.
-- base_rev is the zone revision the draft was built from. It only moves
-- when the draft is (re)loaded from the server, never under a dirty draft,
-- so a save always carries the revision its edits started from and the
-- server rejects it as stale if someone else changed the plan meanwhile.
function Editor:Load(detail,reset)
    self.detail=detail
    if reset or not self.dirty then
        local s=type(detail.settings)=="table" and detail.settings or {}
        self.draft={mode=s.mode=="exact" and "exact" or "ratio",density=tostring(s.density or "9"),weights={},counts={}}
        for k,v in pairs(type(s.weights)=="table" and s.weights or {}) do if type(v)=="number" then self.draft.weights[k]=v end end
        for k,v in pairs(type(s.counts)=="table" and s.counts or {}) do if type(v)=="number" then self.draft.counts[k]=v end end
        self.dirty=false
        self.base_rev=detail.rev
        if reset then self.picking=false;self.order=nil end
    end
    self:Render()
end
-- The server's newer plan is not what this draft was edited from.
function Editor:Conflict()
    return self.dirty and self.detail.rev~=self.base_rev
end
-- Server reply for this editor. data.stale: our base was outdated, load
-- the authoritative plan. data.saved: our own command was accepted; a
-- pause/resume changes no settings, so an unsaved draft survives it and is
-- rebased onto the revision our own command produced.
function Editor:Receive(detail,data)
    local own=self.awaiting
    self.awaiting=nil
    if data.stale then
        self:Load(detail,true)
        self.notice="方案已被其他玩家更新，已载入最新方案；你未保存的修改没有提交。"
        self:Render()
    elseif data.saved then
        -- Only a draft that was current when the command left may be
        -- rebased; a draft already in conflict stays in conflict.
        local rebase=own and (own.cmd=="pause" or own.cmd=="resume") and self.dirty and own.base==self.base_rev
            and not own.conflict and own.rev==own.base
        if rebase then self:Load(detail,false);self.base_rev=detail.rev;self:Render()
        else self:Load(detail,true) end
    else
        self:Load(detail,false)
    end
end
function Editor:Send(cmd,settings)
    local d=self.detail
    if cmd=="save" then
        local fits,why=Fields.CheckCapacity(settings,tonumber(d.n) or 0)
        if not fits then self.notice=why;self:Render();return end
    end
    -- save carries the draft's base revision; pause/resume/template act on
    -- the plan currently shown and carry its revision.
    local rev=cmd=="save" and self.base_rev or d.rev
    self.awaiting={cmd=cmd,base=self.base_rev,rev=rev,conflict=self:Conflict()}
    send({cmd=cmd,zone=d.id,rev=rev,settings=settings})
end
-- Load a plan into the draft (unsaved) without touching the detail.
function Editor:UseSettings(s)
    self.draft={mode=s.mode=="exact" and "exact" or "ratio",density=tostring(s.density or self.draft.density),weights={},counts={}}
    for k,v in pairs(type(s.weights)=="table" and s.weights or {}) do if type(v)=="number" then self.draft.weights[k]=v end end
    for k,v in pairs(type(s.counts)=="table" and s.counts or {}) do if type(v)=="number" then self.draft.counts[k]=v end end
    self.order=nil;self.picking=false;self.dirty=true
    self:Render()
end
function Editor:Field() return self.draft.mode=="exact" and "counts" or "weights" end
function Editor:CanAdd()
    if Fields.SelectionTotal(self.draft)>=Fields.InputCapacity(self.draft,self.detail.n) then
        self.notice="已达到田块孔数上限，请先减少其他作物数量。";self:Render();return false
    end
    return true
end
-- Slot order: crops in the order they were added, then the rest by id.
function Editor:Crops()
    local map=self.draft[self:Field()]
    self.order=self.order or {}
    local seen,out={}, {}
    for _,id in ipairs(self.order) do if (map[id] or 0)>0 and not seen[id] then seen[id]=true;out[#out+1]=id end end
    local rest={};for id,n in pairs(map) do if n>0 and not seen[id] then rest[#rest+1]=id end end
    table.sort(rest);for _,id in ipairs(rest) do out[#out+1]=id end
    self.order=out
    return out
end
function Editor:Change(fn)
    fn();self.dirty=true;self.notice="";self:Render()
end
function Editor:Preview()
    local d=self.detail
    local saved=type(d.settings)=="table" and tostring(d.settings.density)==self.draft.density
    if not saved then return nil end
    local targets=Fields.Targets(self.draft,tonumber(d.use) or 0)
    return targets
end
function Editor:Render()
    local body,d,draft=self.body,self.detail,self.draft
    body:KillAllChildren()
    local top=PANEL_H/2
    label(body,"田块 #"..tostring(d.id):sub(2).." · 种植方案"..(d.configured and "" or "（默认模板）"),-20,top-22,22,{.98,.92,.7,1})
    textbutton(body,"×",PANEL_W/2-22,top-22,function() self.hud:CloseEditor() end,30)
    local nominal=tonumber(d.n or 0)*tonumber(draft.density)
    local total=Fields.SelectionTotal(draft)
    local info=tostring(d.n or 0).." 格 × 每格 "..draft.density.." 孔 · 已选 "..total.."/"..nominal
    if tostring((d.settings or {}).density)==draft.density then info=info.." · 可用 "..tostring(d.use or 0) end
    label(body,info,0,top-50,16)
    -- Second line: what keeps the plan from the nominal capacity.
    local notes={}
    if total>nominal then notes[#notes+1]="超出上限 "..(total-nominal).."，减少数量后才能保存" end
    if (tonumber(d.spacing_lost) or 0)>0 and tostring((d.settings or {}).density)==draft.density then notes[#notes+1]="原生孔距限制少 "..d.spacing_lost.." 孔" end
    if (tonumber(d.wh) or 0)>0 then
        local why={};for code,n in pairs(type(d.withheld_reasons)=="table" and d.withheld_reasons or {}) do why[#why+1]=(REASON_TEXT[code] or code)..n end
        notes[#notes+1]="暂缓 "..d.wh.."（"..table.concat(why,"，").."）"
    end
    if (tonumber(d.offgrid) or 0)>0 then notes[#notes+1]="网格外作物 "..d.offgrid.." 株保留" end
    if (tonumber(d.miss) or 0)>0 then notes[#notes+1]="缺种 "..d.miss end
    if d.over then notes[#notes+1]="数量超出容量 "..d.over end
    if d.unsafe then notes[#notes+1]="该密度无法安全排布" end
    local review=type(d.review)=="table" and d.review
    if review then
        notes={(review.reason=="merge" and "田块合并：方案不同，" or "田块分割：精确数量需重新确认，").."保存即确认；此前不会新种。"}
    end
    local line=label(body,table.concat(notes," · "),0,top-72,15,review and {1,.65,.45,1} or {.9,.75,.55,1})
    line:SetRegionSize(PANEL_W-24,22)
    -- Mode and density rows.
    label(body,"模式",-PANEL_W/2+40,top-100,17)
    for i,mode in ipairs({"ratio","exact"}) do
        textbutton(body,(draft.mode==mode and "● " or "")..MODE_TEXT[mode],-110+(i-1)*130,top-100,function()
            self:Change(function()
                if mode==draft.mode then return end
                -- Seed the other mode from the current targets so the switch
                -- shows meaningful numbers.
                local field=mode=="exact" and "counts" or "weights"
                if next(draft[field])==nil then
                    local src=mode=="exact" and (self:Preview() or d.targets) or draft.counts
                    for k,v in pairs(type(src)=="table" and src or {}) do if type(v)=="number" and v>0 then draft[field][k]=math.min(field=="weights" and Fields.MAX_WEIGHT or Fields.MAX_COUNT,v) end end
                end
                draft.mode=mode
            end)
        end,18)
    end
    label(body,draft.mode=="exact" and "整个田块合计" or "按比例填满全部可用孔",160,top-100,14,{.75,.75,.7,1})
    label(body,"每格孔数",-PANEL_W/2+50,top-126,17)
    for i,value in ipairs(Fields.DENSITIES) do
        textbutton(body,(draft.density==value and "●" or "")..value,-130+(i-1)*58,top-126,function()
            self:Change(function() draft.density=value end)
        end,18)
    end
    if self.picking then self:RenderPicker(top-160) else self:RenderSlots(top-178) end
    -- Footer.
    local bottom=-PANEL_H/2
    textbutton(body,d.paused and "恢复此田块" or "暂停此田块",-170,bottom+42,function()
        self:Send(d.paused and "resume" or "pause")
    end,18)
    textbutton(body,"使用默认模板",-30,bottom+42,function()
        self:Send("template")
    end,18)
    local conflict=self:Conflict()
    textbutton(body,self.dirty and "● 保存方案" or (review and "确认方案" or "保存方案"),130,bottom+42,function()
        local out={mode=draft.mode,density=draft.density,weights={},counts={}}
        for k,v in pairs(draft.weights) do if v>0 then out.weights[k]=v end end
        for k,v in pairs(draft.counts) do if v>0 then out.counts[k]=v end end
        self:Send("save",out)
    end,20)
    if conflict and not self.picking then
        -- Someone else's plan arrived under this unsaved draft. Saving still
        -- sends the draft's base revision, so the server answers stale and
        -- nothing is overwritten; the player can also drop the draft here.
        textbutton(body,"放弃我的修改，载入最新方案",0,bottom+66,function() self:Load(self.detail,true) end,16)
    end
    if review and not self.picking and not conflict then
        for i,alt in ipairs(review.alternatives or {}) do
            if i<=2 and type(alt)=="table" and type(alt.settings)=="table" then
                textbutton(body,"载入合并前方案"..i.."："..describe(alt.settings),0,bottom+66+(i-1)*20,function()
                    self:UseSettings(alt.settings)
                end,14)
            end
        end
    end
    local status=self.notice~="" and self.notice or (d.paused and "此田块已暂停：其他田块照常工作。" or "编辑期间此田块暂停，关闭后按方案继续。")
    if conflict then status="此田块方案已被其他玩家更新：你的修改基于旧版本，不能直接保存。" end
    label(body,status,0,bottom+16,15,{.8,.85,.75,1})
end
-- Pagination: page n of a list of count items, per items a page; returns
-- the clamped page and the page count (always at least one page).
local function clamp_page(page,count,per)
    local pages=math.max(1,math.ceil(count/per))
    return math.max(1,math.min(pages,math.floor(tonumber(page) or 1))),pages
end
local SLOTS_PER_PAGE=SLOT_COLUMNS*SLOT_ROWS
local PICKS_PER_ROW,PICK_ROWS=7,3
-- Slot items: every plan crop, then one add slot while below MAX_CROPS, so
-- a full page always leaves the add slot reachable on the next page.
function Editor:SlotCount()
    local n=#self:Crops()
    return n+(n<Fields.MAX_CROPS and 1 or 0)
end
function Editor:PageArrows(y,page,pages,set)
    if pages<=1 then return end
    -- Outside the slot columns (x ±168, buttons ±210), between the two slot
    -- rows, so they never meet the footer or status rows.
    textbutton(self.body,"◀",-PANEL_W/2+14,y,function() set(math.max(1,page-1)) end,26)
    textbutton(self.body,"▶",PANEL_W/2-14,y,function() set(math.min(pages,page+1)) end,26)
    label(self.body,page.."/"..pages,PANEL_W/2-14,y-24,13,{.85,.8,.65,1})
end
-- Crops the server offered, in order, without malformed entries; ids
-- already in the plan but missing from the server list stay editable in
-- the slots (never dropped by the picker).
function Editor:PickerCrops()
    local out,seen={}, {}
    for _,crop in ipairs(type(self.detail.crops)=="table" and self.detail.crops or {}) do
        if type(crop)=="table" and type(crop.id)=="string" and not seen[crop.id] then seen[crop.id]=true;out[#out+1]=crop end
    end
    return out
end
function Editor:RenderSlots(y0)
    local body,d,draft=self.body,self.detail,self.draft
    local field=self:Field()
    local crops=self:Crops()
    local preview=self:Preview() or {}
    local stock=type(d.stock)=="table" and d.stock or {}
    local have=type(d.have)=="table" and d.have or {}
    local limit=field=="weights" and Fields.MAX_WEIGHT or Fields.MAX_COUNT
    local total=0;for _,n in pairs(draft[field]) do total=total+n end
    local page,pages=clamp_page(self.slot_page,self:SlotCount(),SLOTS_PER_PAGE)
    self.slot_page=page
    self:PageArrows(y0-56,page,pages,function(p) self.slot_page=p;self:Render() end)
    for slot_index=1,SLOTS_PER_PAGE do
        local index=(page-1)*SLOTS_PER_PAGE+slot_index
        local col,row=(slot_index-1)%SLOT_COLUMNS,math.floor((slot_index-1)/SLOT_COLUMNS)
        local x,y=(col-(SLOT_COLUMNS-1)/2)*112,y0-row*112
        local crop=crops[index]
        local slot=body:AddChild(ImageButton("images/hud.xml","inv_slot.tex"))
        slot:ForceImageSize(64,64);slot.scale_on_focus=false;slot.move_on_click=false
        slot:SetPosition(x,y)
        if crop then
            local info=cropinfo(crop)
            local image=icon(body,info.icon,48);image:SetPosition(x,y)
            local amount=draft[field][crop] or 0
            label(body,(field=="weights" and "×" or "")..amount,x+20,y+20,18,{1,1,1,1})
            label(body,info.name,x,y-40,14)
            local target=preview[crop]
            -- Two short lines so neighbouring columns never overlap.
            local short=target and math.max(0,target-(have[crop] or 0)-(stock[info.seed] or 0)) or 0
            local colour=short>0 and {1,.6,.45,1} or {.8,.8,.75,1}
            label(body,(target and ("目标"..target) or "目标?").." 已种"..(have[crop] or 0),x,y-54,12,colour)
            label(body,"库存"..(stock[info.seed] or 0)..(short>0 and (" 缺"..short) or ""),x,y-67,12,colour)
            textbutton(body,"－",x-40,y+2,function()
                self:Change(function() draft[field][crop]=math.max(0,amount-1);if draft[field][crop]==0 then draft[field][crop]=nil end end)
            end,24)
            textbutton(body,"＋",x+42,y+2,function()
                if amount>=limit or field=="counts" and total>=Fields.MAX_COUNT then return end
                if not self:CanAdd() then return end
                self:Change(function() draft[field][crop]=amount+1 end)
            end,24)
            slot:SetHoverText(info.name.."：用 －/＋ 调整，减到 0 即移除")
        elseif index==#crops+1 and #crops<Fields.MAX_CROPS then
            label(body,"＋",x,y,34,{.9,.85,.6,1})
            label(body,"添加作物",x,y-40,14)
            slot:SetOnClick(function() self.picking=true;self:Render() end)
        end
    end
    if #crops==0 then label(body,"空方案：此田块不会新种作物（已有作物照常照料）。",0,y0-180,14,{.85,.75,.6,1}) end
end
-- Show the slot page holding crop id (after adding or picking a crop).
function Editor:ShowCrop(id)
    for i,crop in ipairs(self:Crops()) do
        if crop==id then self.slot_page=math.ceil(i/SLOTS_PER_PAGE);return end
    end
end
function Editor:RenderPicker(y0)
    local body,d=self.body,self.detail
    local field=self:Field()
    label(body,"选择作物（只是种植方案，不放入物品）",0,y0,16,{.95,.9,.7,1})
    textbutton(body,"取消",PANEL_W/2-50,y0,function() self.picking=false;self:Render() end,18)
    local crops=self:PickerCrops()
    local stock=type(d.stock)=="table" and d.stock or {}
    local per_page=PICKS_PER_ROW*PICK_ROWS
    local page,pages=clamp_page(self.pick_page,#crops,per_page)
    self.pick_page=page
    local chosen=self.draft[field]
    local full=#self:Crops()>=Fields.MAX_CROPS
    for slot_index=1,per_page do
        local crop=crops[(page-1)*per_page+slot_index]
        if crop then
            local col,row=(slot_index-1)%PICKS_PER_ROW,math.floor((slot_index-1)/PICKS_PER_ROW)
            local x,y=(col-(PICKS_PER_ROW-1)/2)*64,y0-44-row*70
            local info=cropinfo(crop.id)
            local seed=type(crop.seed)=="string" and crop.seed or info.seed
            local inplan=(chosen[crop.id] or 0)>0
            local b=body:AddChild(ImageButton("images/hud.xml","inv_slot.tex"))
            b:ForceImageSize(52,52);b.scale_on_focus=false;b.move_on_click=false;b:SetPosition(x,y)
            if inplan then b:SetImageNormalColour(.55,.85,.55,1) end
            local image=icon(body,info.icon,40);image:SetPosition(x,y)
            label(body,tostring(stock[seed] or 0),x+16,y-16,13,{1,1,1,1})
            if inplan then label(body,"●",x-17,y+17,14,{.7,1,.7,1}) end
            b:SetHoverText(info.name.." · 库存种子 "..tostring(stock[seed] or 0)..(inplan and " · 已在方案中" or ""))
            b:SetOnClick(function()
                -- A crop already in the plan only jumps to its slot; a new
                -- one is added unless the plan already has MAX_CROPS kinds.
                if not inplan and full then self.notice="方案最多 "..Fields.MAX_CROPS.." 种作物。";self:Render();return end
                if not inplan and not self:CanAdd() then return end
                self.picking=false
                if inplan then self:ShowCrop(crop.id);self:Render();return end
                self:Change(function()
                    self.order=self:Crops();self.order[#self.order+1]=crop.id
                    self.draft[field][crop.id]=1
                    self:ShowCrop(crop.id)
                end)
            end)
        end
    end
    if pages>1 then
        -- Below the third picker row, above the footer buttons.
        local y=y0-44-PICK_ROWS*70+19
        textbutton(body,"◀ 上一页",-110,y,function() self.pick_page=math.max(1,page-1);self:Render() end,16)
        label(body,page.."/"..pages,0,y,15,{.85,.8,.65,1})
        textbutton(body,"下一页 ▶",110,y,function() self.pick_page=math.min(pages,page+1);self:Render() end,16)
    end
end

-- HUD root ------------------------------------------------------------------------
local ZoneHud=Class(Widget,function(self,owner)
    Widget._ctor(self,"AgriZoneHud")
    self.owner=owner
    self.badges,self.entries={}, {}
    self.poll,self.ping=0,0
    self.open_id,self.pending_id,self.editor=nil,nil,nil
    self:StartUpdating()
    if owner and owner.ListenForEvent then
        self.inst:ListenForEvent("onremove",function() self:Shutdown() end,owner)
    end
end)
function ZoneHud:RobotsNear()
    local owner=self.owner
    if not (owner and owner:IsValid()) then return false end
    local x,_,z=owner.Transform:GetWorldPosition()
    return #TheSim:FindEntities(x,0,z,ROBOT_RANGE,{"agribot"})>0
end
function ZoneHud:Active()
    local owner=self.owner
    return owner and owner:IsValid() and owner.HUD and TheFrontEnd:GetActiveScreen()==owner.HUD
        and not owner:HasTag("playerghost")
end
function ZoneHud:SetList(list)
    local keep={}
    for i,entry in ipairs(list) do
        if i<=C.ZONE_LIST_MAX and validentry(entry) then
            keep[entry.id]=true
            self.entries[entry.id]=entry
            local badge=self.badges[entry.id]
            if not badge then badge=self:AddChild(Badge(self,entry.id));self.badges[entry.id]=badge end
            badge:SetData(entry)
        end
    end
    for id,badge in pairs(self.badges) do
        if not keep[id] then badge:Kill();self.badges[id]=nil;self.entries[id]=nil end
    end
    if self.open_id and not keep[self.open_id] then self:CloseEditor() end
    if self.editor then self.editor:MoveToFront() end
end
function ZoneHud:Clear()
    for id,badge in pairs(self.badges) do badge:Kill() end
    self.badges,self.entries={}, {}
    self:CloseEditor()
end
function ZoneHud:Toggle(id)
    if self.open_id==id or self.pending_id==id then self:CloseEditor();return end
    self:CloseEditor()
    self.pending_id=id
    send({cmd="open",zone=id})
end
function ZoneHud:CloseEditor(silent)
    local id=self.open_id or self.pending_id
    if id and not silent then send({cmd="close",zone=id}) end
    self.open_id,self.pending_id=nil,nil
    if self.editor then self.editor:Kill();self.editor=nil end
end
function ZoneHud:Receive(data)
    if type(data.list)=="table" then self:SetList(data.list) end
    local detail=type(data.detail)=="table" and data.detail or nil
    if detail and validentry(detail) then
        if data.open and self.pending_id==detail.id then
            self.pending_id,self.open_id=nil,detail.id
            if self.editor then self.editor:Kill() end
            self.editor=self:AddChild(Editor(self,detail))
            self.ping=C.ZONE_PING_INTERVAL
        elseif self.editor and self.open_id==detail.id then
            self.editor:Receive(detail,data)
        end
        if self.badges[detail.id] then self.badges[detail.id]:SetData(detail) end
        if data.saved then self.ping=math.min(self.ping,2.5) end
    end
    if type(data.closed)=="string" and (data.closed==self.open_id or data.closed==self.pending_id) then
        self:CloseEditor(true)
    end
    if type(data.error)=="string" then
        if self.editor and (data.zone==nil or data.zone==self.open_id) then
            self.editor.notice=data.error;self.editor:Render()
        elseif self.owner and self.owner.components and self.owner.components.talker then
            self.owner.components.talker:Say(data.error)
        end
    elseif self.editor and data.saved then
        self.editor.notice="已保存：空出的孔位按新方案补种，已长好的作物不会被铲除。";self.editor:Render()
    end
end
-- Upper centre of a zone on screen: middle of the tile centres'
-- horizontal extent, above the highest projected zone corner.
local function anchor(entry)
    local minx,maxx,maxy=math.huge,-math.huge,-math.huge
    local wx0,wx1,wz0,wz1=math.huge,-math.huge,math.huge,-math.huge
    local pts=entry.pts
    for i=1,#pts,2 do
        local x,z=pts[i],pts[i+1]
        local sx,sy=TheSim:GetScreenPos(x,0,z)
        minx,maxx,maxy=math.min(minx,sx),math.max(maxx,sx),math.max(maxy,sy)
        wx0,wx1,wz0,wz1=math.min(wx0,x),math.max(wx1,x),math.min(wz0,z),math.max(wz1,z)
    end
    for _,c in ipairs({{wx0-2,wz0-2},{wx0-2,wz1+2},{wx1+2,wz0-2},{wx1+2,wz1+2}}) do
        local _,sy=TheSim:GetScreenPos(c[1],0,c[2]);maxy=math.max(maxy,sy)
    end
    return (minx+maxx)/2,maxy
end
local function nearest(owner,entry)
    local x,_,z=owner.Transform:GetWorldPosition()
    local best=math.huge
    for i=1,#entry.pts,2 do local dx,dz=entry.pts[i]-x,entry.pts[i+1]-z;best=math.min(best,dx*dx+dz*dz) end
    return math.sqrt(best)
end
function ZoneHud:Layout(active)
    local w,h,prop,hud=scales()
    local k=prop*hud
    local open_pos
    for id,badge in pairs(self.badges) do
        local entry=self.entries[id]
        local visible=false
        if active and entry and nearest(self.owner,entry)<=HIDE_DISTANCE then
            local sx,sy=anchor(entry)
            sy=sy+(BADGE_H/2+8)*k
            if sx>-BADGE_W*k and sx<w+BADGE_W*k and sy>-BADGE_H*k and sy<h+BADGE_H*k then
                visible=true
                badge.content:SetScale(hud)
                badge:SetPosition(sx,sy,0)
                if id==self.open_id then open_pos={sx,sy} end
            end
        end
        if visible then badge:Show() else badge:Hide() end
    end
    if self.editor then
        if open_pos then
            local half_w,half_h=PANEL_W/2*k,PANEL_H/2*k
            local x=open_pos[1]+(BADGE_W/2+12)*k+half_w
            if x+half_w>w then x=open_pos[1]-(BADGE_W/2+12)*k-half_w end
            x=math.max(half_w,math.min(w-half_w,x))
            local y=math.max(half_h,math.min(h-half_h,open_pos[2]))
            self.editor.content:SetScale(hud)
            self.editor:SetPosition(x,y,0)
            self.editor:Show()
        else self.editor:Hide() end
    end
end
function ZoneHud:OnUpdate(dt)
    local owner=self.owner
    if not (owner and owner:IsValid()) then self:Clear();return end
    local active=self:Active()
    self.poll=self.poll-dt
    if self.poll<=0 then
        self.poll=C.ZONE_POLL_INTERVAL
        if self:RobotsNear() then
            if active then send({cmd="list"}) end
        elseif next(self.badges)~=nil then self:Clear() end
    end
    if self.open_id then
        local entry=self.entries[self.open_id]
        if owner:HasTag("playerghost") or not owner.HUD then self:CloseEditor()
        elseif entry and nearest(owner,entry)>C.ZONE_EDIT_DISTANCE then self:CloseEditor()
        else
            self.ping=self.ping-dt
            if self.ping<=0 then self.ping=C.ZONE_PING_INTERVAL;send({cmd="ping",zone=self.open_id}) end
        end
    end
    self:Layout(active)
end
function ZoneHud:Shutdown()
    if self.shut then return end
    self.shut=true
    self:CloseEditor()
end
function ZoneHud:Kill()
    self:Shutdown()
    ZoneHud._base.Kill(self)
end
return ZoneHud
