-- P0 detector: epic+hostile bosses and lordfruitfly count; friendly epic or dead bosses do not.
local function ent(guid,prefab,tags,dead)
    local t={GUID=guid,prefab=prefab,_tags=tags,components={health={IsDead=function()return dead end}}}
    function t:HasTag(n) return self._tags[n]==true end
    function t:IsValid() return true end
    return t
end
local list={
    ent(1,"deerclops",{epic=true,hostile=true}),
    ent(2,"lordfruitfly",{epic=true,lordfruitfly=true}),
    ent(3,"friendlyepic",{epic=true}),
    ent(4,"bearger",{epic=true,hostile=true},true),
}
TheSim={FindEntities=function()return list end}
TUNING={FROG_RAIN_PRECIPITATION=0.8,FROG_RAIN_MOISTURE=2500}
TheWorld={state={isspring=false},components={}}
package.loaded["agri/util"]={Valid=function(e)return e~=nil and e:IsValid()end}
local D=require("agri/emergency_detector")
local out=D.Scan({center={x=0,z=0},settings={radius=16}})
assert(out["boss:1"],"hostile boss detected")
assert(out["lordfruitfly:2"],"lord fruit fly detected")
assert(not out["boss:3"],"non-hostile epic ignored")
assert(not out["boss:4"],"dead boss ignored")
TheWorld={state={isspring=true,israining=true,precipitationrate=1,moistureceil=3000},
    components={frograin={OnSave=function()return{frogcap=4}end}}}
list={}
out=D.Scan({center={x=0,z=0},settings={radius=16}})
assert(out.frograin,"frog rain detected")
package.loaded["agri/util"]=nil
return "4 scenarios: hostile boss, lordfruitfly, friendly/dead epic ignored, frog rain"
