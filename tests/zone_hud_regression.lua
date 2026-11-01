-- Codex widget logic tests. These do not certify real rendering/click focus.
Class=function(base,ctor)
    if not ctor then ctor=base;base=nil end
    local c={_base=base,_ctor=ctor};c.__index=c
    return setmetatable(c,{__index=base,__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})
end
local Widget=Class(function(self,name)
    self.name=name;self.children={};self.visible=true;self.inst={ListenForEvent=function()end}
end)
function Widget:AddChild(child)child.parent=self;self.children[#self.children+1]=child;return child end
function Widget:KillAllChildren()for _,c in ipairs(self.children)do c:Kill()end;self.children={}end
function Widget:Kill()self.killed=true end
function Widget:Show()self.visible=true end
function Widget:Hide()self.visible=false end
function Widget:SetPosition(x,y,z)self.pos={x=x,y=y,z=z}end
function Widget:SetText(v)self.caption=v end
function Widget:SetString(v)self.string=v end
function Widget:SetOnClick(fn)self.click=fn end
for _,name in ipairs({"SetScaleMode","SetMaxPropUpscale","SetScale","SetClickable","SetSize","SetTint","SetColour","SetTextSize","SetTextColour","SetTextFocusColour","SetRegionSize","SetHAlign","SetVAlign","EnableWordWrap","ForceImageSize","SetImageNormalColour","SetImageFocusColour","SetHoverText","StartUpdating","MoveToFront","MoveToBack"})do Widget[name]=function()end end
local Text=Class(Widget,function(self,font,size,text)Widget._ctor(self,"Text");self.string=text end)
local Item=Class(Widget,function(self)Widget._ctor(self,"Item")end)
package.loaded["widgets/widget"]=Widget;package.loaded["widgets/text"]=Text
for _,name in ipairs({"image","imagebutton","textbutton"})do package.loaded["widgets/"..name]=Item end
SCALEMODE_PROPORTIONAL=1;MAX_HUD_SCALE=1.25;RESOLUTION_X=1280;RESOLUTION_Y=720;BODYTEXTFONT="font"
GetInventoryItemAtlas=function()return "atlas"end
STRINGS={NAMES={}}
local defs={};for i=1,24 do local id=string.format("crop%02d",i);defs[id]={seed=id.."_seeds",product=id}end
package.preload["prefabs/farm_plant_defs"]=function()return {PLANT_DEFS=defs}end
local U=require("agri/util");local sent={}
package.loaded["agri/network"]={SendZone=function(v)sent[#sent+1]=U.Copy(v)end}
TheSim={GetScreenSize=function()return 1280,720 end,GetScreenPos=function(_,x,y,z)return 500+x*20,300+z*15 end,FindEntities=function()return {{}}end}
TheFrontEnd={GetHUDScale=function()return 1 end}
local ZoneHud=require("widgets/agrizonehud")
function Widget:SetHoverText(v)self.hover=v end
local function button(root,text)
    local textvalue=root.caption or root.hover
    if root.click and textvalue and textvalue:find(text,1,true)then return root end
    for _,c in ipairs(root.children)do local b=button(c,text);if b then return b end end
end
local function hastext(root,text)
    if type(root.string)=="string"and root.string:find(text,1,true)then return true end
    for _,c in ipairs(root.children)do if hastext(c,text)then return true end end
end
local function addslot(root)
    if root.click and not root.caption and not root.hover then return root end
    for _,c in ipairs(root.children)do local b=addslot(c);if b then return b end end
end
local function detail(n)
    local crops,weights={},{}
    for i=1,24 do local id=string.format("crop%02d",i);crops[#crops+1]={id=id,seed=id.."_seeds",product=id};if i<=(n or 2)then weights[id]=1 end end
    return {id="z1",rev=1,pts={2,2},n=4,d=8,m="ratio",nom=32,use=32,pl=0,tg={},miss=0,st="ok",
        settings={mode="ratio",density="8",weights=weights,counts={}},targets={},have={},stock={},crops=crops}
end
local function fixture(n)
    sent={};local owner={HUD={},IsValid=function()return true end,HasTag=function()return false end,
        ListenForEvent=function()end,Transform={GetWorldPosition=function()return 2,0,2 end}}
    TheFrontEnd.GetActiveScreen=function()return owner.HUD end
    local hud=ZoneHud(owner);local d=detail(n)
    hud:Receive({list={d}});hud:Toggle("z1");hud:Receive({open=true,detail=d})
    assert(hud.editor and hud.open_id=="z1")
    return hud,d
end
local errors,passed={},0
local function test(name,fn)local ok,err=pcall(fn);if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end end
test("floating badge opens the correct zone and close releases it",function()
    local h=fixture();assert(sent[1].cmd=="open"and sent[1].zone=="z1")
    h:CloseEditor();assert(sent[#sent].cmd=="close"and sent[#sent].zone=="z1"and not h.editor)
end)
test("heartbeat preserves an unsaved local crop edit",function()
    local h,d=fixture();h.editor:Change(function()h.editor.draft.weights.crop01=3 end)
    h:Receive({detail=U.Copy(d)})
    assert(h.editor.dirty and h.editor.draft.weights.crop01==3)
end)
test("save sends edited settings and a revision for the displayed zone",function()
    local h=fixture();h.editor:Change(function()h.editor.draft.weights.crop01=3 end)
    local b=button(h.editor.body,"保存");assert(b,"missing save control");b.click()
    local last=sent[#sent];assert(last.cmd=="save"and last.zone=="z1"and last.rev==1 and last.settings.weights.crop01==3)
end)
test("invalid coordinate data never produces a badge",function()
    local h=fixture();h:Receive({list={{id="z9",pts={math.huge,2}}}})
    assert(h.badges.z9==nil)
end)

test("all legacy crop slots remain reachable after page one",function()
    local h=fixture(12);assert(#h.editor:Crops()==12)
    local nextpage=button(h.editor.body,"▶");assert(nextpage);nextpage.click()
    assert(h.editor.slot_page==2 and hastext(h.editor.body,"crop12"))
end)
test("a full page still exposes add and later crop-picker pages",function()
    local h=fixture(8);button(h.editor.body,"▶").click()
    assert(h.editor.slot_page==2);local add=addslot(h.editor.body);assert(add);add.click()
    assert(h.editor.picking);local nextpage=button(h.editor.body,"下一页");assert(nextpage);nextpage.click()
    local crop=button(h.editor.body,"crop24");assert(crop);crop.click()
    assert(h.editor.draft.weights.crop24==1 and h.editor.slot_page==2 and not h.editor.picking)
end)
test("background revision changes cannot silently overwrite another player's edit",function()
    local h,d=fixture();h.editor:Change(function()h.editor.draft.weights.crop01=3 end)
    local refreshed=U.Copy(d);refreshed.rev=2;refreshed.settings.weights.crop01=5
    h:Receive({detail=refreshed});button(h.editor.body,"保存").click()
    local request=sent[#sent]
    assert(request.cmd~="save"or request.rev==1,"dirty draft adopted a newer revision and could silently overwrite it")
end)
test("badge progress uses whole-plan totals rather than hole capacity",function()
    local h,d=fixture();d.m="exact";d.use=32;d.pl=25;d.tt=8;d.td=2;d.st="editing"
    h:Receive({list={d}})
    assert(h.badges.z1.status.string:find("2/8",1,true))
    assert(not h.badges.z1.status.string:find("他人",1,true))
end)
local function buttons(root,text,out)
    out=out or {};if root.click and root.caption==text then out[#out+1]=root end
    for _,c in ipairs(root.children)do buttons(c,text,out)end;return out
end
local function lastsavecount()
    local n=0;for _,v in ipairs(sent)do if v.cmd=="save"then n=n+1 end end;return n
end
test("eight-hole draft refuses plus at total eight",function()
    for _,mode in ipairs({"ratio","exact"})do
        local h,d=fixture();d.n=1;d.use=8;d.settings.mode=mode
        d.settings.weights=mode=="ratio"and{crop01=7,crop02=1}or{}
        d.settings.counts=mode=="exact"and{crop01=7,crop02=1}or{}
        h.editor:Load(d,true);local field=mode=="exact"and"counts"or"weights"
        local plus=buttons(h.editor.body,"＋");assert(#plus>=2);plus[1].click()
        assert(h.editor.draft[field].crop01==7,"plus exceeded cap in "..mode)
    end
end)
test("four tiles allow32 but reject33 and adding another crop at cap",function()
    local h,d=fixture();d.settings.weights={crop01=16,crop02=15};h.editor:Load(d,true)
    buttons(h.editor.body,"＋")[2].click();assert(h.editor.draft.weights.crop02==16)
    buttons(h.editor.body,"＋")[2].click();assert(h.editor.draft.weights.crop02==16)
    local add=addslot(h.editor.body)
    if add then
        add.click();local b=button(h.editor.body,"crop03");if b then b.click()end
        assert(not h.editor.draft.weights.crop03,"picker bypassed total cap")
    end
end)
test("legacy oversized draft is visible but cannot save until corrected",function()
    local h,d=fixture();d.n=1;d.use=8;d.settings.weights={crop01=28,crop02=3};h.editor:Load(d,true)
    assert(h.editor.draft.weights.crop01==28,"legacy plan silently discarded")
    local before=lastsavecount();local save=button(h.editor.body,"保存");if save then save.click()end
    assert(lastsavecount()==before,"legacy over-cap draft submitted save")
    h.editor:Change(function()h.editor.draft.weights={crop01=7,crop02=1}end)
    button(h.editor.body,"保存").click();assert(lastsavecount()==before+1)
end)
test("density decrease and heartbeat shrink cannot send oversized save",function()
    local h,d=fixture();d.n=1;d.use=8;d.settings.weights={crop01=8};h.editor:Load(d,true)
    h.editor:Change(function()h.editor.draft.density="6"end)
    local before=lastsavecount();local b=button(h.editor.body,"保存");if b then b.click()end
    assert(lastsavecount()==before,"density decrease bypassed cap")
    h,d=fixture();h.editor:Change(function()h.editor.draft.weights={crop01=16,crop02=16}end)
    d.n=1;d.rev=d.rev+1;h.editor:Load(d,false)
    before=lastsavecount();b=button(h.editor.body,"保存");if b then b.click()end
    assert(lastsavecount()==before,"shrunk zone sent oversized draft")
end)
test("mode switches and imported review settings cannot bypass nominal cap",function()
    local h,d=fixture();d.n=1;d.use=8;d.settings.weights={crop01=7,crop02=1}
    d.settings.counts={crop01=8,crop02=1};h.editor:Load(d,true)
    button(h.editor.body,"精确数量").click()
    local before=lastsavecount();button(h.editor.body,"保存").click();assert(lastsavecount()==before)
    h.editor:UseSettings({mode="ratio",density="8",weights={crop01=28,crop02=3},counts={}})
    button(h.editor.body,"保存").click();assert(lastsavecount()==before)
end)
if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." zone HUD draft and request scenarios (rendering not certified)"
